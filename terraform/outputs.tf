# output "ssh_command" {
  # description = "Command to connet instances"
  # value       = "ssh ubuntu@${aws_instance.cloud1[each.key].public_ip}"
# }

output "IP" {
  description = "Just the IP of all instances"
  value       = {
    for key, value in aws_instance.cloud1 : key => value.public_ip
  }
}
