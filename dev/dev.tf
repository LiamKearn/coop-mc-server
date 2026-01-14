provider "aws" {
  region = "us-east-1"
}

module "minecraft" {
  source = "../modules/proxied_minecraft"

  aws_region = "us-east-1"
  aws_availability_zone = "us-east-1b"
  name_prefix = "dev"
  personal_email_address = var.personal_email_address
  minecraft_ip_address = var.minecraft_ip_address
  minecraft_state_volume_id = var.minecraft_state_volume_id
}
