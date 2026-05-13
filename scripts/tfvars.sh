#!/bin/bash

set -euo pipefail

# TODO: add error messages + regex on instance names (meme si le toset de terraform n'accepte pas les double) + add color for UX

GREEN='\033[0;32m'
NC='\033[0m'

# source if terraform.tfvars is created
if [ -f ../terraform/terraform.tfvars ]; then
  source ../terraform/terraform.tfvars
fi

# ask for region type ans path ssh
read -p "AWS region [${aws_region:-eu-north-1}]: " input
aws_region=${input:-${aws_region:-eu-north-1}}

read -p "Instance type [${instance_type:-t3.small}]: " input
instance_type=${input:-${instance_type:-t3.small}}

read -p "SSH public key path [${public_key_path:-~/.ssh/cloudone.pub}]: " input
public_key_path=${input:-${public_key_path:-~/.ssh/cloudone.pub}}

# project name for s3
while [ -z "$project_name" ]; do
  read -p "Project name [NO DEFAULT]: " input
  project_name=${input:-${project_name}}
done

# get names of instances recu
while [ -z "$instance_count" ] || ! [[ "$instance_count" =~ ^[0-9]+$ ]]; do
  read -p "Number of instances: " instance_count
done

instance_names=""
for i in $(seq 1 $instance_count); do
  read -p "Name of instance $i: " name
  if [ -z "$instance_names" ]; then
    instance_names="\"$name\""
  else
    instance_names="$instance_names,\"$name\""
  fi
done

# get IP host for ingress secu
IP_HOST=$(curl -s ifconfig.me)

# create .tfvars
cat > ../terraform/terraform.tfvars <<EOF
aws_region="${aws_region}"
instance_type="${instance_type}"
public_key_path="${public_key_path}"
project_name="${project_name}"
instance_names=[${instance_names}]
ip_host="${IP_HOST}/32"
EOF

echo -e "${GREEN}terraform.tfvars generated !${NC}"
