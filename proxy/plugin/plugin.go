package plugin

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/robinbraemer/event"
	"go.minekube.com/common/minecraft/component"
	gateconfig "go.minekube.com/gate/pkg/edition/java/config"
	"go.minekube.com/gate/pkg/edition/java/proto/version"
	"go.minekube.com/gate/pkg/edition/java/proxy"
	"math"
	"net"
	"time"
)

type Eggpress struct {
	keep   time.Time
	ec2    *ec2.Client
	inst   string
	server proxy.RegisteredServer
	cfg    gateconfig.Config
}

func NewEggpressPlugin(targetInstanceId string, targetInstancePrivateIp net.Addr) proxy.Plugin {
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

			// Register the target server with gate
			server, err := p.Register(proxy.NewServerInfo("coop", targetInstancePrivateIp))
			if err != nil {
				return fmt.Errorf("unable to register server, %v", err)
			}

			egg.server = server
			egg.cfg = p.Config()

			return nil
		},
	}
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

	_, err := e.ec2.StartInstances(event.Player().Context(), &ec2.StartInstancesInput{
		InstanceIds: []string{e.inst},
	})
	if err != nil {
		panic(err)
	}

	fmt.Println("Started instance:", e.inst)
}
