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

resource "aws_subnet" "cloudone_a" {
  # checkov:skip=CKV_AWS_130: use public IP for Ansible instead of bastion
  vpc_id                  = aws_vpc.cloudone.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-subnet-a"
  }
}

resource "aws_subnet" "cloudone_b" {
  # checkov:skip=CKV_AWS_130: use public IP for Ansible instead of bastion
  vpc_id                  = aws_vpc.cloudone.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-subnet-b"
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

resource "aws_route_table_association" "cloudone_a" {
  subnet_id      = aws_subnet.cloudone_a.id
  route_table_id = aws_route_table.cloudone.id
}


resource "aws_route_table_association" "cloudone_b" {
  subnet_id      = aws_subnet.cloudone_b.id
  route_table_id = aws_route_table.cloudone.id
}


# ==========================================
# AWS LOAD BALANCER
# ==========================================

resource "aws_lb" "cloudone_alb" {
    # checkov:skip=CKV2_AWS_28: We will consider using self-hosted ModSecurity WAF
    # checkov:skip=CKV_AWS_18: Access logging is intentionally disabled
    # checkov:skip=CKV_AWS_91: Access logging is intentionally disabled
    # checkov:skip=CKV_AWS_150: Deletion protection disabled intentionally in dev environment
    name                        = "${var.project_name}-alb"
    internal                    = false
    load_balancer_type          = "application"
    security_groups             = [aws_security_group.alb_sg.id]
    subnets                     = [aws_subnet.cloudone_a.id, aws_subnet.cloudone_b.id]
    drop_invalid_header_fields  = true
    enable_deletion_protection = false
}

resource "aws_lb_target_group" "cloudone_tg" {
    name                = "${var.project_name}-tg"
    port                = 443
    protocol            = "HTTPS"
    vpc_id              = aws_vpc.cloudone.id

    health_check {
        path                = "/wp-login.php"
        protocol            = "HTTPS"
        matcher             = "200, 301, 302"
        interval            = 15
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 3
    }
}


resource "aws_lb_listener" "https_frontend" {
    load_balancer_arn       = aws_lb.cloudone_alb.arn
    port                    = "443"
    protocol                = "HTTPS"
    ssl_policy              = "ELBSecurityPolicy-TLS-1-2-2017-01"
    certificate_arn         = aws_acm_certificate.alb_cert.arn

    default_action {
        type                = "forward"
        target_group_arn    = aws_lb_target_group.cloudone_tg.arn
    }

    depends_on = [aws_lb.cloudone_alb]
}

resource "aws_lb_listener" "http_to_https" {
  load_balancer_arn = aws_lb.cloudone_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  depends_on = [aws_lb.cloudone_alb]
}

resource "terraform_data" "duckdns_cname_sync" {
  triggers_replace = [aws_lb.cloudone_alb.dns_name]

  provisioner "local-exec" {
    command = <<-EOT
        CLEAN_TOKEN=$(echo -n "$TOKEN" | tr -d '\r\n\t ' | textclean 2>/dev/null || echo -n "$TOKEN" | tr -cd '[:alnum:]-')
        curl -s -X GET "https://www.duckdns.org/update?domains=$DOMAINS&token=$CLEAN_TOKEN&cname=$CNAME"
    EOT
    
    environment = {
      DOMAINS = var.duck_domains[0]
      TOKEN   = trimspace(data.aws_kms_secrets.duckdns.plaintext["token"])
      CNAME   = aws_lb.cloudone_alb.dns_name
    }
  }
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

# --- instance SG

resource "aws_security_group" "cloudone" {
# checkov:skip=CKV_AWS_277: attached to EC2 in main.tf
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

# --- ALB SG (public)

resource "aws_security_group" "alb_sg" {
  name          = "${var.project_name}-alb-sg"
  description   = "Security group for Wordpress and Load Balancer"
  vpc_id        = aws_vpc.cloudone.id

  # checkov:skip=CKV_AWS_260:80 should remain open
  ingress {
    description = "HTTP access from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS access from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}


# --- inter SG rules
resource "aws_security_group_rule" "alb_to_instances" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb_sg.id
  source_security_group_id = aws_security_group.cloudone.id
  description              = "Forward traffic to internal instances"
}

resource "aws_security_group_rule" "instances_from_alb_http" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cloudone.id
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "HTTP access from ALB"
}

resource "aws_security_group_rule" "instances_from_alb_https" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cloudone.id
  source_security_group_id = aws_security_group.alb_sg.id
  description              = "HTTPS access from ALB"
}

resource "aws_security_group_rule" "alb_to_instances_https" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb_sg.id
  source_security_group_id = aws_security_group.cloudone.id
  description              = "ALB output to instances via HTTPS"
}
