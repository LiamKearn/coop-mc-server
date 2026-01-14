resource "aws_security_group" "gameserver" {
  name        = "${var.name_prefix}-gameserver"
  description = "Security group for the game server"
}

resource "aws_vpc_security_group_ingress_rule" "java" {
  security_group_id = aws_security_group.gameserver.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 25565
  to_port           = 25565
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "bedrock" {
  security_group_id = aws_security_group.gameserver.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 19132
  to_port           = 19132
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_ingress_rule" "ec2connect" {
  security_group_id = aws_security_group.gameserver.id
  # TODO this could be un-hardcoded...
  cidr_ipv4   = "18.206.107.24/29"
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ipv4" {
  security_group_id = aws_security_group.gameserver.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "ipv6" {
  security_group_id = aws_security_group.gameserver.id
  cidr_ipv6         = "::/0"
  ip_protocol       = "-1"
}

resource "aws_iam_instance_profile" "gameserver" {
  name = "${var.name_prefix}-gameserver"
  role = aws_iam_role.gameserver.name
}

resource "aws_iam_role" "gameserver" {
  name = "${var.name_prefix}-gameserver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "gameserver_instance" {
  role = aws_iam_role.gameserver.id

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

resource "aws_instance" "proxy" {
  tags = {
    Name = "${var.name_prefix}-proxy"
  }

  ami = "ami-TODO"

  instance_type = "t4g.nano"

}

resource "aws_instance" "gameserver" {
  tags = { Name = "${var.name_prefix}-gameserver" }

  # Nushell command to deregister previous AMI if needed (THIS DOESN'T DELETE SNAPSHOTS):
  # ^aws --region us-east-1 ec2 deregister-image --image-id (^aws --region us-east-1 ec2 describe-images --filters Name=name,Values=minecraft | from json | get Images | first | get ImageId)
  # Minecraft AMI built with Packer, See: ./ami/aws-gameserver.pkr.hcl
  ami = "ami-0dad37aad8bc5d67d"

  instance_type        = "t4g.large"
  security_groups      = [aws_security_group.gameserver.name]
  iam_instance_profile = aws_iam_instance_profile.gameserver.name

  availability_zone = var.aws_availability_zone
}

resource "aws_sns_topic" "personal-alarms" {
  name = "${var.name_prefix}-personal-alarms"
}

resource "aws_sns_topic_subscription" "personal_alarms_email" {
  topic_arn = aws_sns_topic.personal-alarms.arn
  protocol  = "email"
  endpoint  = var.personal_email_address
}

# Nushell example:
# let instance_id = ^aws ec2 describe-instances --region us-east-1 --filters Name=tag:Name,Values=prod-gameserver --filters Name=instance-state-name,Values=running | from json | get Reservations | first | get Instances | first | get InstanceId
# ^aws cloudwatch get-metric-data --metric-data-queries $'[{"Id":"playercountQuery","MetricStat":{"Metric":{"Namespace":"coopmcserver","MetricName":"playercount","Dimensions":[{"Name":"InstanceId","Value":"($instance_id)"}]},"Period":5,"Stat":"Maximum"},"ReturnData":true}]' --start-time ((date now) - 20min | format date "%+") --end-time (date now | format date "%+") --region us-east-1
resource "aws_cloudwatch_metric_alarm" "stop_instance_on_zero_players" {
  alarm_name          = "${var.name_prefix}-stop-instance-when-no-players"
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
    aws_sns_topic.personal-alarms.arn,
  ]

  dimensions = {
    InstanceId = aws_instance.gameserver.id
  }
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
  instance_id = aws_instance.gameserver.id
  volume_id   = data.aws_ebs_volume.mcstate.id
}

data "aws_eip" "eip" {
  public_ip = var.minecraft_ip_address
}

resource "aws_eip_association" "eip_association" {
  instance_id   = aws_instance.gameserver.id
  allocation_id = data.aws_eip.eip.id
}
