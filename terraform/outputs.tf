output "angie_ip" {
  description = "instance of angie load balancer"
  value       = aws_eip.angie_lb.public_ip
}

output "instances_ips" {
  value = {
    for k, v in aws_instance.cloudone : k => {
      public  = v.public_ip
      private = v.private_ip
    }
  }
}
