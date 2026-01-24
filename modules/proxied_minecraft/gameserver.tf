resource "aws_instance" "gameserver" {
  tags = { Name = "${var.name_prefix}-gameserver" }

  # Nushell command to deregister previous AMI if needed (THIS DOESN'T DELETE SNAPSHOTS):
  # ^aws --region us-east-1 ec2 deregister-image --image-id (^aws --region us-east-1 ec2 describe-images --filters Name=name,Values=minecraft-gameserver | from json | get Images | first | get ImageId)
  # Minecraft AMI built with Packer, See: ./ami/aws-gameserver.pkr.hcl
  ami = "ami-03dafbd48908fe83b"

  instance_type = "t4g.large"

  iam_instance_profile = aws_iam_instance_profile.gameserver.name

  subnet_id       = aws_subnet.public.id
  # TODO: use aws_network_interface and aws_network_interface_sg_attachment
  # to stop having to recreate the instance when changing security groups
  security_groups = [aws_security_group.gameserver.id]
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
