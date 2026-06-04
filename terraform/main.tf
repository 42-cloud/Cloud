data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_kms_secrets" "duckdns" {
  secret {
    name    = "token"
    payload = var.duckdns_token_encrypted
  }
}

resource "aws_instance" "cloudone" {
  for_each               = toset(var.instance_names)
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.cloudone.key_name
  ebs_optimized          = true
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.cloudone.id]

  subnet_id              = index(tolist(toset(var.instance_names)), each.value) % 2 == 0 ? aws_subnet.cloudone_a.id : aws_subnet.cloudone_b.id

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
  # checkov:skip=CKV_AWS_126:Detailed monitoring is disabled to avoid additional CloudWatch costs.
}


# ==========================================
# CERTS
# ==========================================
resource "tls_private_key" "local_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "cloudone_selfsigned" {
  private_key_pem = tls_private_key.local_key.private_key_pem

  subject {
    common_name  = "${var.duck_domains[0]}.duckdns.org"
    organization = "CloudOne"
  }

  dns_names = ["${var.duck_domains[0]}.duckdns.org"]
  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb_cert" {
  private_key      = tls_private_key.local_key.private_key_pem
  certificate_body = tls_self_signed_cert.cloudone_selfsigned.cert_pem
  lifecycle {
    create_before_destroy = true
  }
}

# ==========================================
# DYNAMIC BINDING OF INSTANCES TO LOAD BALANCER TARGET GROUP
# ==========================================

resource "aws_lb_target_group_attachment" "cloudone_attachment" {
    for_each                = toset(var.instance_names)
    target_group_arn        = aws_lb_target_group.cloudone_tg.arn
    target_id               = aws_instance.cloudone[each.key].id
    port                    = 443
}

# ==========================================
# DYNAMIC INVENTORY
# ==========================================

resource "local_file" "dynamic_inventory" {
  depends_on = [aws_instance.cloudone]
  content  = join("\n", concat(
    ["[wordpress]"],
    [for name, instance in aws_instance.cloudone :
        join(" ", [
        name,
        "ansible_host=${instance.public_ip != null ? instance.public_ip : instance.private_ip}",
        "ansible_user=ubuntu",
        "ansible_ssh_private_key_file=${replace(var.public_key_path, ".pub", "")}",
        "global_duckdns_domain=${trimspace(element(var.duck_domains, index(keys(aws_instance.cloudone), name)))}"
      ])
    ]
  ))
  filename              = "../ansible/inventory/inventory.ini"
  directory_permission  = "0755"
  file_permission       = "0644"
}
