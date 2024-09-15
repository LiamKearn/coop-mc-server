variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_availability_zone" {
    description = "AWS availability zone"
    type        = string
    default     = "us-east-1b"
}

variable "personal_public_key" {
    description = "Personal public key"
    type        = string
}

variable "personal_ip_cidr" {
    description = "Personal IP CIDR"
    type        = string
}

variable "minecraft_ip_address" {
    description = "Minecraft IP address"
    type        = string
}

variable "minecraft_state_volume_id" {
    description = "Minecraft state volume ID"
    type        = string
}

terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 4.16"
        }
    }

    required_version = ">= 1.2.0"
}

provider "aws" {
    region = var.aws_region
}

resource "aws_security_group" "allow_ec2_connect" {
    name        = "allow_ec2_connect"
    description = "Allows EC2 connect for my region (18.206.107.24/29)"
}

resource "aws_vpc_security_group_ingress_rule" "allow_ec2connect_ingress" {
    security_group_id = aws_security_group.allow_ec2_connect.id
    # TODO this could be un-hardcoded...
    cidr_ipv4         = "18.206.107.24/29"
    from_port         = 22
    ip_protocol       = "tcp"
    to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_personal_ingress" {
    security_group_id = aws_security_group.allow_ec2_connect.id
    cidr_ipv4         = var.personal_ip_cidr
    from_port         = 22
    ip_protocol       = "tcp"
    to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_minecraft_ingress" {
    security_group_id = aws_security_group.allow_ec2_connect.id
    cidr_ipv4         = "0.0.0.0/0"
    from_port         = 25565
    ip_protocol       = "tcp"
    to_port           = 25565
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
    security_group_id = aws_security_group.allow_ec2_connect.id
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
    security_group_id = aws_security_group.allow_ec2_connect.id
    cidr_ipv6         = "::/0"
    ip_protocol       = "-1"
}

resource "aws_key_pair" "personal_key" {
    key_name   = "personal-key"
    public_key = var.personal_public_key
}

resource "aws_instance" "mc_server" {
    ami = "ami-0b947c5d5516fa06e"
    instance_type = "t4g.medium"
    key_name = aws_key_pair.personal_key.key_name
    security_groups = [aws_security_group.allow_ec2_connect.name]
    user_data = "${file("./scripts/start.sh")}"
    availability_zone = var.aws_availability_zone
}

data "aws_ebs_volume" "mcstate" {
    most_recent = true
    filter {
        name   = "volume-id"
        values = [var.minecraft_state_volume_id]
    }
}

resource "aws_volume_attachment" "ebs_att" {
    device_name = "/dev/sdf"
    instance_id = aws_instance.mc_server.id
    volume_id   = data.aws_ebs_volume.mcstate.id
}

data "aws_eip" "coop_eip" {
    public_ip = var.minecraft_ip_address
}

resource "aws_eip_association" "coop_eip_association" {
    instance_id   = aws_instance.mc_server.id
    allocation_id = data.aws_eip.coop_eip.id
}
