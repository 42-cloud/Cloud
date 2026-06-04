output "alb_dns" {
  description = "Public entry point : load balancer"
  value       = aws_lb.cloudone_alb.dns_name
}

output "instances_ips" {
  value = {
    for k, v in aws_instance.cloudone : k => {
      public  = v.public_ip
      private = v.private_ip
    }
  }
}
