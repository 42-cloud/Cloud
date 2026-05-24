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
  role = aws_iam_role.cloudone.name # On pointe sur le rôle existant
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

resource "aws_subnet" "cloudone" {
  vpc_id                  = aws_vpc.cloudone.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.project_name}-subnet"
  }
}

resource "aws_internet_gateway" "cloudone" {
  vpc_id = aws_vpc.cloudone.id
  tags = {
    Name = "${var.project_name}-igw"
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

# ==========================================
# FIREWALL
# ==========================================
resource "aws_default_security_group" "default" {
    vpc_id      = aws_vpc.cloudone.id
    tags = {
        Name = "${var.project_name}-default-sg-restricted"
    }
}
resource "aws_security_group" "cloudone" {
  name          = "${var.project_name}-sg"
  description   = "Security group for Wordpress and Angie proxy"
  vpc_id        = aws_vpc.cloudone.id

  ingress {
    description = "SSH access for Ansible"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ip_host]
  }

  ingress {
    description = "HTTP access for Angie"
    from_port   = 8080 # check ansible wordpress_expose_http
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS access for Angie"
    from_port   = 8443 # check ansible wordpress_expose_https
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --- OUTGOING (EGRESS) ---
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

  # can be necessary for some ansible tasks (apt install, docker pull)
  egress {
    description = "DNS resolving via TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}
