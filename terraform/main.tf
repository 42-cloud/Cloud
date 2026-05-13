data "aws_ami" "ubuntu" {
  most_recent = true
  owners = ["099720109477"]
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "cloud1" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t3.small"
  subnet_id = aws_subnet.cloudone.id
  vpc_security_group_ids = [aws_security_group.cloudone.id]
  key_name = aws_key_pair.cloudone.key_name
  tags = {
    Name = "cloudone"
  }
}
