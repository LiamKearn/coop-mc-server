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

