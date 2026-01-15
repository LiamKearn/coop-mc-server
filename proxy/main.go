package main

import (
	"os"
	"fmt"
	"net"
	"github.com/liamkearn/coop-mc-server/proxy/plugin"
	"go.minekube.com/gate/cmd/gate"
	"go.minekube.com/gate/pkg/edition/java/proxy"
)

func main() {
	targetInstanceId := os.Getenv("TARGET_EC2_INSTANCE_ID")
	if targetInstanceId == "" {
		fmt.Println("TARGET_EC2_INSTANCE_ID is not set")
		os.Exit(1)
	}

	targetInstanceIp := os.Getenv("TARGET_EC2_INSTANCE_PRIVATE_IP")
	if targetInstanceIp == "" {
		fmt.Println("TARGET_EC2_INSTANCE_PRIVATE_IP is not set")
		os.Exit(1)
	}

	targetInstanceIpAddr := &net.TCPAddr{
		IP: net.ParseIP(targetInstanceIp),
		Port: 25565,
	}

	proxy.Plugins = append(proxy.Plugins,
		plugin.NewEggpressPlugin(targetInstanceId, targetInstanceIpAddr),
	)

	fmt.Println("Starting")

	gate.Execute()

	fmt.Println("Done")
}
