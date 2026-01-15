packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "minecraft-gameserver" {
  ami_name      = "minecraft-gameserver"
  instance_type = "t4g.large"
  region        = "us-east-1"

  # Amazon Linux 2023 kernel-6.12 AMI
  source_ami = "ami-026a407703c5d38e5"

  ssh_username = "ec2-user"
}

build {
  name = "minecraft-gameserver"
  sources = [
    "source.amazon-ebs.minecraft-gameserver"
  ]

  provisioner "shell" {
    script = "scripts/provision-gameserver.sh"
  }
}

