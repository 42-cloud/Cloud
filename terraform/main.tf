data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "cloud1" {
  for_each = toset(var.instance_names)
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.cloudone.id
  vpc_security_group_ids = [aws_security_group.cloudone.id]
  key_name               = aws_key_pair.cloudone.key_name
  ebs_optimized          = true

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # Impose IMDSv2
  }
  
  tags = {
    Name = "${var.project_name}-${each.value}"
  }
}

resource "aws_eip" "wordpress_eip" {
  for_each = toset(var.instance_names)
  
  instance = aws_instance.cloud1[each.key].id
  domain   = "vpc"
  tags = {
    Name = "${var.project_name}-eip-${each.value}"
  }
}

resource "local_file" "dynamic_inventory" {
  content  = join("\n", concat(
    ["[wordpress]"],
    [for name, eip in aws_eip.wordpress_eip : "${name} ansible_host=${eip.public_ip} ansible_user=ubuntu"]
  ))
  filename              = "../ansible/inventory/inventory.ini"
  directory_permission  = "0755"
  file_permission       = "0644"
}
