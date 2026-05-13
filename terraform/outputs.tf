output "ssh_command" {
  description = "Command to connet instance"
  value       = "ssh ubuntu@${aws_instance.cloud1.public_ip}"
}

output "IP" {
  description = "Just the IP"
  value       = aws_instance.cloud1.public_ip
}
