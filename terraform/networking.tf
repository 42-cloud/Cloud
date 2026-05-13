resource "aws_key_pair" "cloudone" {
  key_name   = "cloudone-key"
  public_key = file(var.public_key_path)
}

resource "aws_vpc" "cloudone" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "cloudone-vpc"
  }
}

resource "aws_subnet" "cloudone" {
  vpc_id                  = aws_vpc.cloudone.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "cloudone-subnet"
  }
}

resource "aws_internet_gateway" "cloudone" {
  vpc_id = aws_vpc.cloudone.id
  tags = {
    Name = "cloudone-igw"
  }
}

resource "aws_route_table" "cloudone" {
  vpc_id = aws_vpc.cloudone.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloudone.id
  }
}

resource "aws_route_table_association" "cloudone" {
  subnet_id      = aws_subnet.cloudone.id
  route_table_id = aws_route_table.cloudone.id
}

resource "aws_security_group" "cloudone" {
  name   = "cloudone-sg"
  vpc_id = aws_vpc.cloudone.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ip_host]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
