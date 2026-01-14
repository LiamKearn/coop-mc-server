provider "aws" {
  region = var.aws_region
}

resource "aws_security_group" "dev_allow_minecraft_map_viewer_ingress" {
  name        = "dev_allow_minecraft_map_viewer_ingress"
  description = "Allows ingress traffic for viewing the minecraft map"
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_minecraft_map_viewer_ingress" {
  security_group_id = aws_security_group.dev_allow_minecraft_map_viewer_ingress.id
  cidr_ipv4         = var.personal_ip_cidr
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_security_group" "dev_allow_minecraft_ingress" {
  name        = "dev_allow_minecraft_ingress"
  description = "Allows minecraft ingress traffic for game-server activity"
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_minecraft_ingress" {
  security_group_id = aws_security_group.dev_allow_minecraft_ingress.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 25565
  ip_protocol       = "tcp"
  to_port           = 25565
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_minecraft_bedrock_ingress" {
  security_group_id = aws_security_group.dev_allow_minecraft_ingress.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 19132
  ip_protocol       = "udp"
  to_port           = 19132
}

resource "aws_security_group" "dev_allow_administration_ingress" {
  name        = "dev_allow_administration_ingress"
  description = "Allows ingress traffic for administration purposes"
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_ec2connect_ingress" {
  security_group_id = aws_security_group.dev_allow_administration_ingress.id
  # TODO this could be un-hardcoded...
  cidr_ipv4   = "18.206.107.24/29"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_ingress_rule" "dev_allow_personal_ingress" {
  security_group_id = aws_security_group.dev_allow_administration_ingress.id
  cidr_ipv4         = var.personal_ip_cidr
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_security_group" "dev_allow_all_egress" {
  name        = "dev_allow_all_egress"
  description = "Allows all egress traffic"
}

resource "aws_vpc_security_group_egress_rule" "dev_allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.dev_allow_all_egress.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "dev_allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.dev_allow_all_egress.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1"
}

resource "aws_key_pair" "dev_personal_key" {
  key_name   = "dev_personal-key"
  public_key = var.personal_public_key
}

resource "aws_iam_role" "dev_mc_instance_role" {
  name = "dev-mc-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dev_mc_instance_policy" {
  role = aws_iam_role.dev_mc_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "dev_mc_instance" {
  name = "mc-instance-profile"
  role = aws_iam_role.dev_mc_instance_role.name
}

resource "aws_instance" "dev_mc_server" {
  # Minecraft AMI built with Packer, See: ./ami/aws-minecraft.pkr.hcl
  ami = "ami-0365ec0debd4c3808"

  instance_type = "t4g.medium"
  key_name      = aws_key_pair.dev_personal_key.key_name
  security_groups = [
    aws_security_group.dev_allow_all_egress.name,
    aws_security_group.dev_allow_administration_ingress.name,
    aws_security_group.dev_allow_minecraft_ingress.name,
  ]
  iam_instance_profile = aws_iam_instance_profile.dev_mc_instance.name

  user_data         = <<-EOF
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
    Name = "dev-mc-server"
  }
}

# TODO: Check that it initialises userdata first.
# Stop the instance after creation, the proxy should be starting it when needed.
# resource "aws_ec2_instance_state" "dev_mc_server_stopped" {
#   instance_id = aws_instance.dev_mc_server.id
#   state       = "stopped"
#   depends_on  = [aws_instance.dev_mc_server]
# }

resource "aws_sns_topic" "dev_liam_alarm_notifications" {
  name = "dev-liam-alarm-notifications"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dev_liam_alarm_notifications.arn
  protocol  = "email"
  endpoint  = "lkearney999@gmail.com"
}

# Nushell example:
# let instance_id = ^aws ec2 describe-instances --region us-east-1 --filters Name=tag:Name,Values=prod-mc-serves --filters Name=instance-state-name,Values=running | from json | get Reservations | first | get Instances | first | get InstanceId
# ^aws cloudwatch get-metric-data --metric-data-queries $'[{"Id":"playercountQuery","MetricStat":{"Metric":{"Namespace":"coopmcserver","MetricName":"playercount","Dimensions":[{"Name":"InstanceId","Value":"($instance_id)"}]},"Period":5,"Stat":"Maximum"},"ReturnData":true}]' --start-time ((date now) - 20min | format date "%+") --end-time (date now | format date "%+") --region us-east-1
resource "aws_cloudwatch_metric_alarm" "dev_stop_instance_on_zero_players" {
  alarm_name          = "devStopInstanceWhenNoPlayers"
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 0
  namespace           = "coopmcserver"
  metric_name         = "playercount"
  evaluation_periods  = 4   # 4 periods x 5 min = 20 minutes
  period              = 300 # 5 minutes
  statistic           = "Maximum"
  alarm_description   = "Stops the EC2 instance if there are 0 players for 20 minutes"

  treat_missing_data = "missing"

  alarm_actions = [
    "arn:aws:automate:${var.aws_region}:ec2:stop",
    aws_sns_topic.dev_liam_alarm_notifications.arn
  ]

  dimensions = {
    InstanceId = aws_instance.prod_mc_server.id
  }
}

data "aws_ebs_volume" "dev_mcstate" {
  most_recent = true
  filter {
    name   = "volume-id"
    values = [var.minecraft_state_volume_id]
  }
}

resource "aws_volume_attachment" "dev_ebs_att" {
  device_name = "/dev/sdf"
  instance_id = aws_instance.dev_mc_server.id
  volume_id   = data.aws_ebs_volume.dev_mcstate.id
}

data "aws_eip" "dev_coop_eip" {
  public_ip = var.minecraft_ip_address
}

resource "aws_eip_association" "dev_coop_eip_association" {
  instance_id   = aws_instance.dev_mc_server.id
  allocation_id = data.aws_eip.dev_coop_eip.id
}
