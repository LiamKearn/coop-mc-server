variable "personal_email_address" {
  description = "Personal Email Address for SNS Alarms"
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

variable "minecraft_floodgate_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Floodgate key"
  type        = string
}
