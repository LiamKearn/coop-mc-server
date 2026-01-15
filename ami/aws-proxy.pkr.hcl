packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "minecraft-proxy" {
  ami_name      = "minecraft-proxy"
  instance_type = "t4g.nano"
  region        = "us-east-1"

  # Amazon Linux 2023 kernel-6.12 AMI
  source_ami = "ami-026a407703c5d38e5"

  ssh_username = "ec2-user"
}

build {
  name = "minecraft-proxy"
  sources = [
    "source.amazon-ebs.minecraft-proxy"
  ]

  provisioner "shell" {
    script = "scripts/provision-proxy.sh"
  }

  provisioner "file" {
    source      = "proxy/proxy"
    destination = "/home/proxy/proxy"
  }

  provisioner "file" {
    source      = "proxy/config.yml"
    destination = "/home/proxy/config.yml"
  }

  provisioner "file" {
    source      = "proxy/server.toml"
    destination = "/home/proxy/server.toml"
  }

  provisioner "shell" {
    inline = [
      "sudo chown proxy:proxy /home/proxy",
      "sudo chmod u+x /home/proxy/proxy",
      "sudo chown proxy /home/proxy/proxy"
    ]
  }
}

