resource "aws_instance" "proxy" {
  tags = {
    Name = "${var.name_prefix}-proxy"
  }

  # Nushell command to deregister previous AMI if needed (THIS DOESN'T DELETE SNAPSHOTS):
  # ^aws --region us-east-1 ec2 deregister-image --image-id (^aws --region us-east-1 ec2 describe-images --filters Name=name,Values=minecraft-proxy | from json | get Images | first | get ImageId)
  # Minecraft Proxy AMI built with Packer, See: ./ami/aws-proxy.pkr.hcl
  ami = "ami-08df709007efd68c1"

  user_data = <<-EOF
  #cloud-config
  write_files:
    - path: /home/proxy/proxy.env
      owner: proxy:proxy
      permissions: '0644'
      content: |
        TARGET_EC2_INSTANCE_ID=${aws_instance.gameserver.id}
        TARGET_EC2_INSTANCE_PRIVATE_IP=${aws_instance.gameserver.private_ip}
  EOF

  instance_type = "t4g.nano"

  iam_instance_profile = aws_iam_instance_profile.proxy.name

  subnet_id                   = aws_subnet.public.id
  # TODO: use aws_network_interface and aws_network_interface_sg_attachment
  # to stop having to recreate the instance when changing security groups
  security_groups             = [aws_security_group.proxy.id]
  associate_public_ip_address = false
}

data "aws_eip" "eip" {
  public_ip = var.minecraft_ip_address
}

resource "aws_eip_association" "eip_association" {
  instance_id   = aws_instance.proxy.id
  allocation_id = data.aws_eip.eip.id
}

