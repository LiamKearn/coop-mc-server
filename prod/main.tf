provider "aws" {
    region = var.aws_region
}

# resource "aws_security_group" "prod_allow_minecraft_map_viewer_ingress" {
#     name        = "allow_minecraft_map_viewer_ingress"
#     description = "Allows ingress traffic for viewing the minecraft map"
# }
#
# resource "aws_vpc_security_group_ingress_rule" "prod_allow_minecraft_map_viewer_ingress" {
#     security_group_id = aws_security_group.prod_allow_minecraft_map_viewer_ingress.id
#     cidr_ipv4         = var.personal_ip_cidr
#     from_port         = 8080
#     ip_protocol       = "tcp"
#     to_port           = 8080
# }

resource "aws_security_group" "prod_allow_minecraft_ingress" {
    name        = "prod_allow_minecraft_ingress"
    description = "Allows minecraft ingress traffic for game-server activity"
}

resource "aws_vpc_security_group_ingress_rule" "prod_allow_minecraft_ingress" {
    security_group_id = aws_security_group.prod_allow_minecraft_ingress.id
    cidr_ipv4         = "0.0.0.0/0"
    from_port         = 25565
    ip_protocol       = "tcp"
    to_port           = 25565
}

resource "aws_vpc_security_group_ingress_rule" "prod_allow_minecraft_bedrock_ingress" {
    security_group_id = aws_security_group.prod_allow_minecraft_ingress.id
    cidr_ipv4         = "0.0.0.0/0"
    from_port         = 19132
    ip_protocol       = "udp"
    to_port           = 19132
}

resource "aws_security_group" "prod_allow_administration_ingress" {
    name        = "prod_allow_administration_ingress"
    description = "Allows ingress traffic for administration purposes"
}

resource "aws_vpc_security_group_ingress_rule" "prod_allow_ec2connect_ingress" {
    security_group_id = aws_security_group.prod_allow_administration_ingress.id
    # TODO this could be un-hardcoded...
    cidr_ipv4         = "18.206.107.24/29"
    from_port         = 22
    ip_protocol       = "tcp"
    to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "prod_allow_personal_ingress" {
    security_group_id = aws_security_group.prod_allow_administration_ingress.id
    cidr_ipv4         = var.personal_ip_cidr
    from_port         = 22
    ip_protocol       = "tcp"
    to_port           = 22
}

resource "aws_security_group" "prod_allow_all_egress" {
    name        = "prod_allow_all_egress"
    description = "Allows all egress traffic"
}

resource "aws_vpc_security_group_egress_rule" "prod_allow_all_traffic_ipv4" {
    security_group_id = aws_security_group.prod_allow_all_egress.id
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "prod_allow_all_traffic_ipv6" {
    security_group_id = aws_security_group.prod_allow_all_egress.id
    cidr_ipv6         = "::/0"
    ip_protocol       = "-1"
}

resource "aws_key_pair" "prod_personal_key" {
    key_name   = "prod_personal-key"
    public_key = var.personal_public_key
}

resource "aws_instance" "prod_mc_server" {
  # Minecraft AMI built with Packer, See: ./ami/aws-minecraft.pkr.hcl
  ami           = "ami-07e0607027b22d739"

    instance_type = "t4g.large"
    key_name = aws_key_pair.prod_personal_key.key_name
    security_groups = [
        aws_security_group.prod_allow_all_egress.name,
        aws_security_group.prod_allow_administration_ingress.name,
        aws_security_group.prod_allow_minecraft_ingress.name,
    ]

    user_data = <<-EOF
      #cloud-config
      runcmd:
        - |
          STATE_DEVICE_NAME=/dev/sdf
          STATE_DIR=/home/mcuser/mcstate
  
          # Ensure the mount point exists
          mkdir -p $STATE_DIR
  
          # Wait for the device to appear
          while [ ! -e "$STATE_DEVICE_NAME" ]; do sleep 1; done
  
          # Create filesystem if not present
          if ! blkid "$STATE_DEVICE_NAME"; then
            mkfs -t ext4 "$STATE_DEVICE_NAME"
          fi
  
          # Add to fstab (avoid duplicates)
          grep -q "$STATE_DEVICE_NAME" /etc/fstab || echo "$STATE_DEVICE_NAME $STATE_DIR ext4 defaults,nofail 0 2" >> /etc/fstab
  
          # Mount it
          mount -a
    EOF
    availability_zone = var.aws_availability_zone

    tags = {
        Name = "prod-mc-server"
    }
}

data "aws_ebs_volume" "prod_mcstate" {
    most_recent = true
    filter {
        name   = "volume-id"
        values = [var.minecraft_state_volume_id]
    }
}

resource "aws_volume_attachment" "prod_ebs_att" {
    device_name = "/dev/sdf"
    instance_id = aws_instance.prod_mc_server.id
    volume_id   = data.aws_ebs_volume.prod_mcstate.id
}

data "aws_eip" "prod_coop_eip" {
    public_ip = var.minecraft_ip_address
}

resource "aws_eip_association" "prod_coop_eip_association" {
    instance_id   = aws_instance.prod_mc_server.id
    allocation_id = data.aws_eip.prod_coop_eip.id
}
