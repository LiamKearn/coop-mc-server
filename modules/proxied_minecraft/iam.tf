data "aws_caller_identity" "current" {}

resource "aws_iam_instance_profile" "proxy" {
  name = "${var.name_prefix}-proxy"
  role = aws_iam_role.proxy.name
}

resource "aws_iam_role" "proxy" {
  name = "${var.name_prefix}-proxy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "proxy_ssm" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_iam_role_policy" "proxy" {
  role = aws_iam_role.proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.gameserver.id}"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
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

resource "aws_iam_role_policy_attachment" "gameserver_ssm" {
  role       = aws_iam_role.gameserver.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
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

