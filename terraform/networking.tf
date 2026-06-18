resource "aws_key_pair" "cloudone" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)
}

resource "aws_vpc" "cloudone" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ==========================================
# KMS
# ==========================================

data "aws_iam_policy_document" "cloudwatch_kms_policy" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
    # checkov:skip=CKV_AWS_111:Full KMS administrative access is explicitly delegated to the root account to prevent key lockout.
    # checkov:skip=CKV_AWS_356:KMS Key Policies require "*" in the resource field to target the key they are attached to
    # checkov:skip=CKV_AWS_109:Root account must retain permission management capabilities (kms:PutKeyPolicy) over its own key
  }

  statement {
    sid    = "Allow CloudWatch Logs to use the key"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${var.project_name}-vpc-flow-logs"]
    }
    # checkov:skip=CKV_AWS_356:KMS key policies must use "*" as the resource. Scope is securely narrowed via the encryption context ARN condition.
  }
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "cloudwatch_key" {
  description             = "KMS Key for CloudWatch Log Group encryption"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.cloudwatch_kms_policy.json
  enable_key_rotation     = true
}

# ==========================================
# OBSERVABILITY & IAM
# ==========================================

resource "aws_flow_log" "cloudone" {
  vpc_id          = aws_vpc.cloudone.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.cloudone.arn
  iam_role_arn    = aws_iam_role.cloudone.arn
}

resource "aws_cloudwatch_log_group" "cloudone" {
  name              = "${var.project_name}-vpc-flow-logs"
  retention_in_days = 3
  kms_key_id        = aws_kms_key.cloudwatch_key.arn

  # checkov:skip=CKV_AWS_338:Short retention of 2 days is intentional to reduce storage costs in this evaluation environment.
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com", "ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}
resource "aws_iam_role" "cloudone" {
  name               = "${var.project_name}-flowlog-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.cloudone.name
}

data "aws_iam_policy_document" "cloudone" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["${aws_cloudwatch_log_group.cloudone.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudone" {
  name   = "${var.project_name}-flowlog-policy"
  role   = aws_iam_role.cloudone.id
  policy = data.aws_iam_policy_document.cloudone.json
}

# ==========================================
# NETWORK & ROUTING
# ==========================================

resource "aws_subnet" "cloudone_public" {
  # checkov:skip=CKV_AWS_130: use public IP for Ansible instead of bastion
  vpc_id                  = aws_vpc.cloudone.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.project_name}-subnet-pub"
  }
}

resource "aws_subnet" "cloudone_backend" {
  # checkov:skip=CKV_AWS_130: use public IP for Ansible instead of bastion
  vpc_id                  = aws_vpc.cloudone.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.project_name}-subnet-back"
  }
}

resource "aws_internet_gateway" "cloudone" {
  vpc_id = aws_vpc.cloudone.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "lb" {
  vpc_id = aws_vpc.cloudone.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cloudone.id
  }
  tags = {
    Name = "${var.project_name}-lb-rt"
  }
}

resource "aws_route_table" "backends" {
  vpc_id = aws_vpc.cloudone.id
  tags = { Name = "${var.project_name}-backends-rt" }
}

resource "aws_route" "backends_nat" {
  route_table_id         = aws_route_table.backends.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.cloudone[var.lb_instance_name].primary_network_interface_id
}

resource "aws_route_table_association" "lb_a" {
  subnet_id      = aws_subnet.cloudone_public.id
  route_table_id = aws_route_table.lb.id
}

resource "aws_route_table_association" "backends_b" {
  subnet_id      = aws_subnet.cloudone_backend.id
  route_table_id = aws_route_table.backends.id
}

# ==========================================
# FIREWALL
# ==========================================
resource "aws_default_security_group" "default" {
    vpc_id      = aws_vpc.cloudone.id
    tags = {
        Name = "${var.project_name}-default-sg-restricted"
    }
}

resource "aws_security_group" "angie_lb" {
  # checkov:skip=CKV2_AWS_5:Attached to EC2 instances via vpc_security_group_ids in main.tf
  # checkov:skip=CKV_AWS_260:Port 80 must be open for Let's Encrypt ACME HTTP-01 challenge and certificate renewal
  name        = "${var.project_name}-lb-sg"
  description = "Security group for Angie load balancer: public facing"
  vpc_id      = aws_vpc.cloudone.id

  ingress {
    description = "Allow private subnet traffic to route out via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
 
  ingress {
    description = "HTTP public traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS public traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access for Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ip_host]
  }

  ingress {
    description     = "step-ca ACME for backends"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    cidr_blocks = ["10.0.2.0/24"]
  }

  egress {
    description     = "SSH to backends for ProxyJump"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "External HTTP requests + update"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "External HTTPS requests + update"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS resolving"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS resolving via TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "backends" {
  # checkov:skip=CKV2_AWS_5:Attached to EC2 instances via vpc_security_group_ids in main.tf
  name        = "${var.project_name}-backends-sg"
  description = "Security group for backend instances: only reachable from Angie LB"
  vpc_id      = aws_vpc.cloudone.id

  ingress {
    description     = "HTTP from Angie LB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.angie_lb.id]
  }

  ingress {
    description     = "SSH from LB for ProxyJump"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.angie_lb.id]
  }

  egress {
    description = "External HTTP requests + update"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "HTTPS from Angie LB for mTLS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.angie_lb.id]
  }

  egress {
    description = "step-ca ACME"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    description = "External HTTPS requests + update"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS resolving"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS resolving via TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
