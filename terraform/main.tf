data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "cloudone" {
  for_each               = toset(var.instance_names)
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.cloudone.key_name
  ebs_optimized          = true
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = each.value == var.lb_instance_name ? [aws_security_group.angie_lb.id] : [aws_security_group.backends.id]

  subnet_id = each.value == var.lb_instance_name ? aws_subnet.cloudone_public.id : aws_subnet.cloudone_backend.id

  source_dest_check = each.value == var.lb_instance_name ? false : true

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
# EIP LB ANGIE
# ==========================================
resource "aws_eip" "angie_lb" {
  instance = aws_instance.cloudone[var.lb_instance_name].id
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-lb-eip"
  }
}

# ==========================================
# DYNAMIC INVENTORY
# ==========================================

resource "local_file" "dynamic_inventory" {
  depends_on = [aws_instance.cloudone, aws_eip.angie_lb]
  content = join("\n", concat(
    ["[angie_lb]"],
    [join(" ", [
      var.lb_instance_name,
      "ansible_host=${aws_eip.angie_lb.public_ip}",
      "ansible_user=ubuntu",
      "ansible_ssh_private_key_file=${replace(var.public_key_path, ".pub", "")}",
      "global_duckdns_domain=${trimspace(element(var.duck_domains, 0))}"
    ])],
    ["", "[backends]"],
    [for name, instance in aws_instance.cloudone :
      join(" ", [
        name,
        "ansible_host=${instance.private_ip}",
        "ansible_user=ubuntu",
        "ansible_ssh_private_key_file=${replace(var.public_key_path, ".pub", "")}",
        "global_duckdns_domain=${trimspace(element(var.duck_domains, index(keys(aws_instance.cloudone), name)))}"
      ])
      if name != var.lb_instance_name
    ],
    ["", "[backends:vars]",
    "ansible_ssh_common_args=-o ProxyJump=ubuntu@${aws_eip.angie_lb.public_ip} -o StrictHostKeyChecking=no -o ForwardAgent=yes",
    "global_lb_private_ip=${aws_instance.cloudone[var.lb_instance_name].private_ip}"
    ]
  ))
  filename             = "../ansible/inventory/inventory.ini"
  directory_permission = "0755"
  file_permission      = "0644"
}
