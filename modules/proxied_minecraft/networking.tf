# ------------------------
# VPC
# ------------------------

resource "aws_vpc" "game" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# ------------------------
# Public Subnet
# ------------------------

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.game.id
  availability_zone       = var.aws_availability_zone
  cidr_block              = "10.0.0.0/17"
  map_public_ip_on_launch = true
}

# ------------------------
# Internet Gateway
# ------------------------

resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.game.id
}

# ------------------------
# Route Table
# ------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.game.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ------------------------
# Security Groups
# ------------------------

resource "aws_security_group" "proxy" {
  name        = "proxy"
  description = "Proxy security group"
  vpc_id      = aws_vpc.game.id
}

resource "aws_security_group" "gameserver" {
  name        = "gameserver"
  description = "Gameserver security group"
  vpc_id      = aws_vpc.game.id
}

# ------------------------
# Security Group Rules
# ------------------------

resource "aws_vpc_security_group_ingress_rule" "proxy_java" {
  security_group_id = aws_security_group.proxy.id
  from_port         = 25565
  to_port           = 25565
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "proxy_bedrock" {
  security_group_id = aws_security_group.proxy.id
  from_port         = 19132
  to_port           = 19132
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"
}

# TODO: This should be exgress to ONLY the gameserver SG AND mojang authentcation servers
# (and also AWS metadata, SSM, etc)
resource "aws_vpc_security_group_egress_rule" "proxy_all" {
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "java_from_proxy" {
  security_group_id            = aws_security_group.gameserver.id
  from_port                    = 25565
  to_port                      = 25565
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.proxy.id
}

resource "aws_vpc_security_group_ingress_rule" "bedrock_from_proxy" {
  security_group_id            = aws_security_group.gameserver.id
  from_port                    = 19132
  to_port                      = 19132
  ip_protocol                  = "udp"
  referenced_security_group_id = aws_security_group.proxy.id
}

resource "aws_vpc_security_group_egress_rule" "gameserver_all" {
  security_group_id = aws_security_group.gameserver.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
