data "aws_secretsmanager_secret_version" "floodgate_key_latest" {
  secret_id = data.aws_secretsmanager_secret.floodgate_key.id
}

data "aws_secretsmanager_secret" "floodgate_key" {
  arn = var.minecraft_floodgate_key_secret_arn
}

