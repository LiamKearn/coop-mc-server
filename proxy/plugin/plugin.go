package plugin

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"net"
	"sync"
	"time"

	"github.com/go-logr/logr"

	"github.com/robinbraemer/event"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudwatch"
	cwtypes "github.com/aws/aws-sdk-go-v2/service/cloudwatch/types"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/aws/aws-sdk-go-v2/service/ec2/types"

	"github.com/aws/aws-sdk-go-v2/aws"

	"go.minekube.com/common/minecraft/component"

	gateconfig "go.minekube.com/gate/pkg/edition/java/config"
	"go.minekube.com/gate/pkg/edition/java/netmc"
	"go.minekube.com/gate/pkg/edition/java/proto/packet"
	"go.minekube.com/gate/pkg/edition/java/proto/state"
	"go.minekube.com/gate/pkg/edition/java/proto/version"
	"go.minekube.com/gate/pkg/edition/java/proxy"
	"go.minekube.com/gate/pkg/gate/proto"
	"go.minekube.com/gate/pkg/util/netutil"
)

// enum for login errors:
type loginState string

const (
	InstanceStarting       loginState = "InstanceStarting"
	InstanceAlreadyRunning loginState = "InstanceAlreadyRunning"
	StartedInstance        loginState = "StartedInstance"
)

type loginContext struct {
	state loginState
}

type Eggpress struct {
	logins     sync.Map // map[uuid.UUID]*loginContext
	ec2        *ec2.Client
	cloudwatch *cloudwatch.Client
	inst       string
	cfg        gateconfig.Config
	log        logr.Logger
	server     proxy.RegisteredServer
}

func NewEggpressPlugin(targetInstanceId string, targetInstancePrivateIp net.Addr) proxy.Plugin {
	return proxy.Plugin{
		Name: "Eggpress",
		Init: func(ctx context.Context, p *proxy.Proxy) error {
			cfg, configLoadError := config.LoadDefaultConfig(ctx)
			if configLoadError != nil {
				return configLoadError
			}

			egg := &Eggpress{
				ec2: ec2.NewFromConfig(cfg, func(o *ec2.Options) {
					// TODO: This can be omitted in prod since it will be inferred.
					o.Region = "us-east-1"
				}),
				cloudwatch: cloudwatch.NewFromConfig(cfg, func(o *cloudwatch.Options) {
					o.Region = "us-east-1"
				}),
				inst: targetInstanceId,
				log:  logr.FromContextOrDiscard(ctx),
			}

			// In order of rough login flow.
			event.Subscribe(p.Event(), math.MaxInt, egg.onPing)
			event.Subscribe(p.Event(), math.MaxInt, egg.onLogin)
			event.Subscribe(p.Event(), math.MaxInt, egg.onPostLoginEvent)
			event.Subscribe(p.Event(), math.MaxInt, egg.onPlayerChooseInitialServerEvent)
			event.Subscribe(p.Event(), math.MinInt, egg.onServerPostConnectEvent)

			// Register the target server with gate
			server, err := p.Register(proxy.NewServerInfo("coop", targetInstancePrivateIp))
			if err != nil {
				panic(fmt.Sprintf("failed to register target server: %v", err))
			}

			egg.server = server
			egg.cfg = p.Config()

			return nil
		},
	}
}

func (e *Eggpress) onLogin(event *proxy.LoginEvent) {

	// TODO: Whitelist functionality, maybe via AWS DynamoDB or something? Needs
	// to be sync between this proxy and the gameserver itself.
	//
	// event.Deny(&component.Text{
	// 	Content: "You're not whitelisted for the COOP, @me (liam) on discord to be added",
	// })
}

func (e *Eggpress) onPostLoginEvent(event *proxy.PostLoginEvent) {
	ctx := event.Player().Context()

	// Storing map based on ID might collide if multiple players can attempt
	// logins with the same UUID but I don't know enough about Minecraft to
	// know if that's possible at this point, so whatever.
	state := &loginContext{}
	go func() {
		<-event.Player().Context().Done()
		e.logins.Delete(event.Player().ID())
	}()
	defer e.logins.Store(event.Player().ID(), state)

	res, err := e.ec2.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
		InstanceIds: []string{e.inst},
	})

	if err != nil || len(res.Reservations) == 0 || len(res.Reservations[0].Instances) == 0 {
		e.log.Error(err, "No instances found", "instanceId", e.inst)
		event.Player().Disconnect(&component.Text{
			Content: "Unable to find the main gameserver for you at this time, please try again later.",
		})
		return
	}

	instance := res.Reservations[0].Instances[0]

	if instance.State.Name == types.InstanceStateNameRunning {
		e.log.Info("Instance is already running", "instanceId", e.inst)
		state.state = InstanceAlreadyRunning
		return
	}

	if instance.State.Name == types.InstanceStateNameStopped {
		e.log.Info("Starting instance", "instanceId", e.inst)
		if _, err := e.ec2.StartInstances(ctx, &ec2.StartInstancesInput{
			InstanceIds: []string{e.inst},
		}); err != nil {
			e.log.Error(err, "Failed to start instance", "instanceId", e.inst)
			event.Player().Disconnect(&component.Text{
				Content: "Unable to start the main gameserver for you at this time, please try again later.",
			})
		} else {
			e.log.Info("Instance start requested successfully", "instanceId", e.inst)
			state.state = StartedInstance
		}

		return
	}

	if instance.State.Name == types.InstanceStateNameStopping {
		panic("TODO: Handle mid stopping start requests")
	}
}

func (e *Eggpress) onPing(event *proxy.PingEvent) {
	event.Ping().Description = &component.Text{
		Content: version.Protocol(event.Connection().Protocol()).String() + " - via COOP Eggpress Proxy",
	}
}

func (e *Eggpress) getLoginContextOrDisconnect(player proxy.Player) *loginContext {
	val, ok := e.logins.Load(player.ID())
	if !ok {
		e.log.Error(nil, "No login context found for player", "playerId", player.ID())
		player.Disconnect(&component.Text{
			Content: "Couldn't find a login context, please try again later.",
		})
		return nil
	} else {
		return val.(*loginContext)
	}
}

func (e *Eggpress) onPlayerChooseInitialServerEvent(event *proxy.PlayerChooseInitialServerEvent) {
	var loginCtx *loginContext
	loginCtx = e.getLoginContextOrDisconnect(event.Player())
	if loginCtx == nil {
		return
	}

	// Can forward the player directly to the server if it's already running.
	if loginCtx.state == InstanceAlreadyRunning {
		event.SetInitialServer(e.server)
	}

	// We could theoretically check if the instance is running here after it's
	// started but that would extremely unlikely, it's much more likely the
	// instance is still starting so we just send them to to the limbo server
	// for now by doing nothing.
}

func (e *Eggpress) onServerPostConnectEvent(event *proxy.ServerPostConnectEvent) {
	var loginCtx *loginContext
	loginCtx = e.getLoginContextOrDisconnect(event.Player())
	if loginCtx == nil {
		return
	}

	player := event.Player()
	ctx := player.Context()

	// TODO: Scope this to multiple players.
	if event.PreviousServer() == nil && loginCtx.state == StartedInstance {
		// Player is connecting to their first server and we started the instance
		// for them, so send them a message.
		player.SendMessage(&component.Text{
			Content: "The main COOP server is starting up, you will be connected automatically once it's ready. This may take a few minutes.",
		})

		// Start a player context canceled (if they disconnect, timeout it's
		// canceled) watcher to attempt to move them to the main server
		// once it's up.
		go func() {
			attempts := 0
			maxAttempts := 24 // 2 minutes at 5 second intervals
			retry := 5 * time.Second

			ticker := time.NewTicker(retry)
			defer ticker.Stop()

			for {
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
					attempts++
					if e.ping(ctx) {
						e.log.Info("Main server is up, moving player", "playerId", player.ID())
						player.SendMessage(&component.Text{
							Content: "The main COOP server is now online, connecting you now!",
						})
						connRequest := event.Player().CreateConnectionRequest(e.server)
						success := connRequest.ConnectWithIndication(event.Player().Context())
						if !success {
							e.log.Error(nil, "Server came online but failed to connect player to main server", "playerId",
								event.Player().ID())
							event.Player().Disconnect(&component.Text{
								Content: "The main COOP server is online but we were unable to connect you to it, please try again later.",
							})
						} else {
							e.log.Info("Player moved to main server successfully", "playerId", event.Player().ID())
							player.SendMessage(&component.Text{
								Content: "Welcome! You have caused the main server to start up and connected successfully.",
							})
							player.SendMessage(&component.Text{
								Content: "If you disconnect and rejoin it should be much faster, however the server will shut down again after around 20 minutes of inactivity (if there are 0 players online for ~20 minutes) to save on costs.",
							})

							// We need to notify cloudwatch that the instance is
							// active so we send a fake player count:
							if _, err := e.cloudwatch.PutMetricData(ctx, &cloudwatch.PutMetricDataInput{
								Namespace: aws.String("coopmcserver"),
								MetricData: []cwtypes.MetricDatum{
									{
										MetricName: aws.String("playercount"),
										Dimensions: []cwtypes.Dimension{
											{
												Name:  aws.String("InstanceId"),
												Value: aws.String(e.inst),
											},
										},
										Value: aws.Float64(1.0),
									},
								},
							}); err != nil {
								e.log.Error(err, "Failed to send player count metric to cloudwatch", "instance", e.inst, "player", player.ID())
								player.SendMessage(&component.Text{
									Content: "Warning: Failed to update server activity status, the server may shut down unexpectedly.",
								})
								player.SendMessage(&component.Text{
									Content: "If that happens, please rejoin the server and it should start up again and work as intended.",
								})
								player.SendMessage(&component.Text{
									Content: "I really need to fix this... :mokatir: what hurts friend face here.",
								})
							}
						}
						return
					} else {
						e.log.Info("Main server is still offline, waiting...", "playerId", event.Player().ID(), "attempt", attempts)
					}

					if attempts >= maxAttempts {
						e.log.Error(nil, "Max attempts reached, disconnecting player", "playerId", event.Player().ID())
						event.Player().SendMessage(&component.Text{
							Content: "The main COOP server is taking too long to start up for me to automatically forward you, please try again after a 5 minute wait via `/server coop`.",
						})
						return
					}
				}
			}
		}()
	}
}

// Ping pings underlying minecraft server.
func (e *Eggpress) ping(ctx context.Context) bool {
	// Close everything after function.
	c, cancel := context.WithCancel(ctx)
	defer cancel()

	// Get server address.
	addr := e.server.ServerInfo().Addr()

	// Dial to server.
	var dialer net.Dialer
	base, err := dialer.DialContext(c, addr.Network(), addr.String())
	if err != nil {
		return false
	}

	// Create client.
	conn, _ := netmc.NewMinecraftConn(
		c, base, proto.ClientBound,
		time.Duration(e.cfg.ReadTimeout),
		time.Duration(e.cfg.ConnectionTimeout),
		e.cfg.Compression.Level,
	)

	// Perform handshake.
	host, port := netutil.HostPort(addr)
	if err := conn.WritePacket(&packet.Handshake{
		ProtocolVersion: int(version.MinimumVersion.Protocol),
		NextStatus:      int(packet.StatusHandshakeIntent),

		ServerAddress: host,
		Port:          int(port),
	}); err != nil {
		return false
	}

	// Create ping packet.
	ping := &packet.StatusPing{
		RandomID: rand.Int63(),
	}

	// Ping server.
	conn.SetState(state.Status)
	if err := conn.WritePacket(ping); err != nil {
		return false
	}

	// Receive pong.
	pack, err := conn.Reader().ReadPacket()
	if err != nil {
		return false
	}

	// Verify pong.
	registry := state.FromDirection(proto.ServerBound, state.Status, pack.Protocol)
	if id, ok := registry.PacketID(ping); ok && id == pack.PacketID {
		return ping.RandomID == pack.Packet.(*packet.StatusPing).RandomID
	}

	return false
}
