#!/bin/bash

set -euo pipefail

# TODO: add error messages + add color for UX

GREEN='\033[0;32m'
RED='\033[0;31m'
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

project_name=""
# project name for s3
while [ -z "$project_name" ]; do
  read -p "Project name [NO DEFAULT]: " input
  project_name=${input:-${project_name}}
done

# NB : AWS would nevertheless return an error around 30 instances per region
MAX_INSTANCE=300
instance_count=""
# get names of instances recu
while [ -z "$instance_count" ] || ! [[ "$instance_count" =~ ^[0-9]+$ ]] || [ "$instance_count" -lt 1 ] || [ "$instance_count" -gt $MAX_INSTANCE ]; do
  read -p "Number of instances (1-${MAX_INSTANCE}): " instance_count
  if [ "$instance_count" -gt "$MAX_INSTANCE" ]; then
    echo -e "${RED}Error:${NC} There should be between 1 and $MAX_INSTANCE instances."
  fi
done

# validates instance name against regex
instance_names=""
declare -A seen_names
regex='^[a-zA-Z0-9]([a-zA-Z0-9\-]{1,61}[a-zA-Z0-9])?$'



echo -e "${GREEN}Please enter the DuckDNS sub-domains (they should have been priorly booked) :${NC}"
duck_domain=""

while true; do
read -p "DuckDNS subdomain: " dname
if [ -z "$dname" ]; then continue; fi
duck_domain=$dname
break
done


instance_names=""
for i in $(seq 1 "$instance_count"); do
  if [ -z "$instance_names" ]; then
    instance_names="\"node-$i\""
  else
    instance_names="$instance_names,\"node-$i\""
  fi
done

# get IP host for ingress secu
IP_HOST=$(curl -s ifconfig.me)
mkdir -p "$(dirname "$0")/../terraform"

first_instance=$(echo "${instance_names}" | sed 's/[][]//g' | cut -d',' -f1 | tr -d '" ')

# duckdns_token_encrypted="AQICAHh8Rd7AQWTIrwjmthKBrEsxLGjXoqIPpu8jTv1vOgljuQGETJWPy55G4vDKVtnG6GF/AAAAgzCBgAYJKoZIhvcNAQcGoHMwcQIBADBsBgkqhkiG9w0BBwEwHgYJYIZIAWUDBAEuMBEEDORG5dRwya1Y/iH3jwIBEIA/ytExj++v5N0j4oWrPRcDhesqnbweycccunXBRPA9Nz4KNjHXQGd+E185A0bNxM19e0IeEJF+mJ67rM5pO78T"
# create .tfvars
cat > "$(dirname "$0")/../terraform/terraform.tfvars" <<EOF
aws_region="${aws_region}"
instance_type="${instance_type}"
public_key_path="${public_key_path}"
project_name="${project_name}"
duck_domains=["${duck_domain}"]
instance_names=[${instance_names}]
lb_instance_name="${first_instance}"
ip_host="${IP_HOST}/32"
EOF

echo -e "${GREEN}terraform.tfvars generated !${NC}"
