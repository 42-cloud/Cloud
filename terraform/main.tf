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
  tags = {
    Name = "${var.project_name}-${each.value}"
  }
}

resource "local_file" "dynamic_inventory" {
  content  = join("\n", [for name, instance in aws_instance.cloud1 : "[${name}]\nansible_host=${instance.public_ip}"])
  filename = "../ansible/inventory/inventory.ini"
  directory_permission = "0755"
  file_permission = "0644"
}
