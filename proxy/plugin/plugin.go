package plugin

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	"github.com/robinbraemer/event"
	"go.minekube.com/common/minecraft/component"
	"go.minekube.com/gate/pkg/edition/java/proto/version"
	"go.minekube.com/gate/pkg/edition/java/proxy"
	"math"
	"net"
	"time"
)

type Eggpress struct {
	keep time.Time
	ec2  *ec2.Client
	inst string
	server proxy.RegisteredServer
}

// TODO: Add disconnect event which checks if proxy.Proxy.PlayerCount() < 1 and
// then waits some time and stops the instance again.

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
				ec2:  ec2.NewFromConfig(cfg, func(o *ec2.Options) {
					// TODO: This can be omitted in prod since it will be inferred.
					o.Region = "us-east-1"
				}),
				inst: targetInstanceId,
			}

			event.Subscribe(p.Event(), 0, egg.onPing)
			event.Subscribe(p.Event(), math.MaxInt, egg.onPlayerChooseInitialServerEvent)

			addr, err := findTCPAddrFromInstance(ctx, egg.ec2, targetInstanceId)
			if err != nil {
				return fmt.Errorf("unable to find instance address, %v", err)
			}

			server, err := p.Register(proxy.NewServerInfo("target", addr))
			if err != nil {
				return fmt.Errorf("unable to register server, %v", err)
			}

			egg.server = server

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
	return addr, nil
}

func (e *Eggpress) onPing(event *proxy.PingEvent) {
	s := fmt.Sprintf("%s - via Eggpress", version.Protocol(event.Connection().Protocol()))
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

	waiter := ec2.NewInstanceRunningWaiter(e.ec2)
	err = waiter.Wait(event.Player().Context(), &ec2.DescribeInstancesInput{
		InstanceIds: []string{e.inst},
	}, 2*time.Minute)
	if err != nil {
		// panic:
		panic(err)
	}

	event.SetInitialServer(e.server)

	fmt.Println("Instance is running")
}
