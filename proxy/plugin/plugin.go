package plugin

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/robinbraemer/event"
	"go.minekube.com/common/minecraft/component"
	gateconfig "go.minekube.com/gate/pkg/edition/java/config"
	"go.minekube.com/gate/pkg/edition/java/netmc"
	"go.minekube.com/gate/pkg/edition/java/proto/packet"
	"go.minekube.com/gate/pkg/edition/java/proto/state"
	"go.minekube.com/gate/pkg/edition/java/proto/version"
	"go.minekube.com/gate/pkg/edition/java/proxy"
	"go.minekube.com/gate/pkg/gate/proto"
	"go.minekube.com/gate/pkg/util/netutil"
	"math"
	"math/rand"
	"net"
	"time"
)

type Eggpress struct {
	keep   time.Time
	ec2    *ec2.Client
	inst   string
	Server proxy.RegisteredServer
	cfg    gateconfig.Config
}

func NewEggpressPlugin(targetInstanceId string) proxy.Plugin {
	return proxy.Plugin{
		Name: "Eggpress",
		Init: func(ctx context.Context, p *proxy.Proxy) error {
			cfg, err := config.LoadDefaultConfig(ctx)
			if err != nil {
				return fmt.Errorf("unable to load SDK config, %v", err)
			}

			egg := &Eggpress{
				keep: time.Now(),
				ec2: ec2.NewFromConfig(cfg, func(o *ec2.Options) {
					// TODO: This can be omitted in prod since it will be inferred.
					o.Region = "us-east-1"
				}),
				inst: targetInstanceId,
			}

			event.Subscribe(p.Event(), 0, egg.onPing)
			event.Subscribe(p.Event(), math.MaxInt, egg.onPlayerChooseInitialServerEvent)

			// Find the target instance address
			addr, err := findTCPAddrFromInstance(ctx, egg.ec2, targetInstanceId)
			if err != nil {
				return fmt.Errorf("unable to find instance address, %v", err)
			}

			// Register the target server with gate
			server, err := p.Register(proxy.NewServerInfo("target", addr))
			if err != nil {
				return fmt.Errorf("unable to register server, %v", err)
			}

			// Persist the registered server within our gate plugin so we can
			// forward players to it as an initial server.
			egg.Server = server
			egg.cfg = p.Config()

			return nil
		},
	}
}

func findTCPAddrFromInstance(ctx context.Context, client *ec2.Client, instanceId string) (*net.TCPAddr, error) {
	// Describe the specific instance
	resp, err := client.DescribeInstances(ctx, &ec2.DescribeInstancesInput{
		InstanceIds: []string{instanceId},
	})
	if err != nil {
		panic(err)
	}

	if len(resp.Reservations) == 0 || len(resp.Reservations[0].Instances) == 0 {
		panic("instance not found")
	}

	inst := resp.Reservations[0].Instances[0]

	if len(inst.NetworkInterfaces) == 0 || inst.NetworkInterfaces[0].PrivateIpAddress == nil {
		panic("no IPv4 address attached")
	}

	firstIPv4 := *inst.NetworkInterfaces[0].Association.PublicIp

	addr := &net.TCPAddr{
		IP:   net.ParseIP(firstIPv4),
		Port: 25565,
	}

	fmt.Println("Found instance address:", addr.String())

	return addr, nil
}

func (e *Eggpress) onPing(event *proxy.PingEvent) {
	s := fmt.Sprintf("%s - via COOP Eggpress", version.Protocol(event.Connection().Protocol()))
	p := event.Ping()
	t := component.Text{
		Content: s,
	}
	p.Description = &t
}

func (e *Eggpress) onPlayerChooseInitialServerEvent(event *proxy.PlayerChooseInitialServerEvent) {
	wasauth := event.Player().OnlineMode()
	fmt.Println("Player is connecting to server, time since last:", time.Since(e.keep), "WAS AUTH:", wasauth)
	e.keep = time.Now()

	fmt.Println("Starting instance:", e.inst)

	_, err := e.ec2.StartInstances(event.Player().Context(), &ec2.StartInstancesInput{
		InstanceIds: []string{e.inst},
	})
	if err != nil {
		// panic:
		panic(err)
	}

	fmt.Println("Instance start requested")

	// FIXME: This blocks if the client disconnects before the instance is running.

	waiter := ec2.NewInstanceRunningWaiter(e.ec2)
	err = waiter.Wait(event.Player().Context(), &ec2.DescribeInstancesInput{
		InstanceIds: []string{e.inst},
	}, 2*time.Minute)
	if err != nil {
		// panic:
		panic(err)
	}

	for {
		ctx := event.Player().Context()
		if e.Ping(ctx) {
			fmt.Println("Instance is reachable")
			break
		}
		fmt.Println("Instance not yet reachable, waiting...")
		time.Sleep(time.Second)
	}

	event.SetInitialServer(e.Server)

	fmt.Println("Instance is running")
}

// From LazyGate! (https://github.com/kasefuchs/lazygate)
func (e *Eggpress) Ping(ctx context.Context) bool {
	// Close everything after function.
	c, cancel := context.WithCancel(ctx)
	defer cancel()

	// Get server address.
	addr := e.Server.ServerInfo().Addr()

	// Dial to server.
	var dialer net.Dialer
	base, err := dialer.DialContext(c, addr.Network(), addr.String())
	if err != nil {
		return false
	}

	// Create client.
	conn, _ := netmc.NewMinecraftConn(
		c, base, proto.ClientBound,
		time.Duration(e.cfg.ReadTimeout), time.Duration(e.cfg.ConnectionTimeout), e.cfg.Compression.Level,
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
