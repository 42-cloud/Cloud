# Overview

Automated deployment of Wordpress related services using Terraform and Ansible

[![CI/CD Pipeline](https://github.com/42-cloud/Cloud/actions/workflows/security.yml/badge.svg)](https://github.com/42-cloud/Cloud/actions)

[![CI/CD Pipeline](https://github.com/42-cloud/Cloud/actions/workflows/ansible.yml/badge.svg)](https://github.com/42-cloud/Cloud/actions)

# Tasks list

__network and security__
- [ ] only `80` and `443` should be accessible (replace 8080 and 8443)
- [ ] usage of TLS
- [x] network isolation of DB from the internet

__roles__
- [ ] Add `observability` role
- [ ] Wordpress role
  - [ ] Readme for `wordpress` role
  - [x] Molecule tests
  - [ ] PHP My Admin configuration
  - [ ] handler to reload angie
  - [ ] handler to reload wordpress apache

__resilience__
- [ ] dynamic DNS
- [ ] auto-restart if server is rebooted with data preserved

__scalability__
- [ ] parallel deploy to multiple servers

__flexibility__
- [ ] provider-agnostic configuration
- [ ] can create various users with admin rights on EC2, app admin rights on wordpress

__security__
- [x] distroless OCI images via apko/melange
- [x] SBOM generation for all images
- [x] automated CVE scanning via syft + grype
- [x] GitHub Issues automation for CVE reporting
- [x] secrets via file (tmpfs in prod)
- [x] non-root containers
- [ ] GHA release for melange-forge binaries
- [ ] matrix refactor for CVE scan workflow

# Setup

## Prerequisites

All commands are compatible with Ubuntu

```bash
# Ensure local bin (or .local/bin) directory exists
mkdir -p $HOME/bin

# add taskfile
sh -c "$(curl -sSL https://taskfile.dev/install.sh)" -- -d -b $HOME/bin

# add terraform
TERRAFORM_VERSION="1.11.0"
curl -sSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip
unzip -q /tmp/terraform.zip -d $HOME/bin/
rm /tmp/terraform.zip

# add ansible
python3 -m venv $HOME/.ansible_venv
source $HOME/.ansible_venv/bin/activate
pip install --upgrade pip
pip install ansible-core checkov argcomplete
ln -sf $HOME/.ansible_venv/bin/ansible $HOME/bin/ansible
ln -sf $HOME/.ansible_venv/bin/ansible-playbook $HOME/bin/ansible-playbook
deactivate

# add AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install -i $HOME/.local/aws-cli -b $HOME/bin

# GET key details for AWS IAM profile
# AWS Management Console > IAM > Users > Create access key

# Configure AWS CLI
aws configure
# fill details from IAM

```

## Tasks

```bash
# create terraform/terraform.tfvars
task tfvars

# download providers
task init

# check terraform project correctness
task plan

# deploy infrastructure
task apply

# deploy configuration
task ansible:play

```

## Usage

Access the app on `https://cloud1.duckdns.org`


# Stack

## Ubuntu as base OS

### package installation method

- DEB822 (from RFC 822) is the new APT norm to declare package repositories on Debian and Ubuntu. Successor to `.list`. 
  - it relies on key: value pairs for suites, components, architecture
  - every repo has its gpg key

## Automation and Orchestration

### Go-Task

> Task runner and build tool : an alternative to Makefile

- uses YAML
- handles cache more efficiently than Makefile : fingerprinting vs date of last modification
- multiplatform

### Bash script

`tfvars.sh` to check variables and generate `terraform.tfvars`


## Containerization

### Wolfi OS

> A secure Linux distribution

- used as a base layer for all services
- quickly updated in case of CVE
- compatible with packages compiled for glibc

### Melange

> Declarative APK builder : compiles packages from source code

- each service has its own `melange.yaml` build config
- packages are signed with a shared RSA key
- wolfi pipelines are fetched from `wolfi-dev/os` for test support

### Apko

> Image assembler : assembles packages into a _distroless_ image

- **secure** : images don't have shell, reducing attack surface
- **idempotent** : images are identical given the same inputs
- **lightweight** : single layer OCI image

Apko generates:
- SPDX SBOM with all components, licences, and upstream source commits for each package
- _SBOM_ (software bill of materials) which can be used to audit supply chain

UID and GID are `65532` : conventional ID for non-root

### melange-forge

> External library of statically compiled Go binaries for distroless images

- provides healthcheck binaries (`healthcheck-http`, `healthcheck-sql`, `healthcheck-fcgi`) embedded in each image
- replaces shell-based healthchecks (`curl`, `wget`, `mariadb-admin`) which are unavailable in distroless images
- `healthcheck-sql` uses `mlock` to prevent password from being swapped to disk
- passwords are read from files (tmpfs in prod) rather than environment variables
- source: [Kazibuya/melange-forge](https://github.com/Kazibuya/melange-forge)

### Images

| Service | Base | Tag |
|:--|:--|:--|
| Angie | Wolfi | `namichel/angie:1.11.6-amd64` |
| WordPress | Wolfi | `namichel/wordpress:6.9.4-amd64` |
| MariaDB | Wolfi | `namichel/mariadb:12.2.2-amd64` |
| phpMyAdmin | Wolfi | `namichel/phpmyadmin:5.2.3-amd64` |

## Infrastructure as Code

We define a basic network architecture :
 - VPC (virtual private cloud) with subnet to isolate the cloud environment
 - Internet Gateway to bridge VPC with public internet
 - Security group acting as a firewall

__Best practices__

- Restrict SSH to specific IP

### Terraform

> An infrastructure as code tool that defines cloud resources

#### Architecture proposal

_monoserver_

 - `aws_eip` Elastic IP

=> We choose a monoserver architecture for the sake of simplicity

_multi-tier_ (possible evolution)

 - **load balancer** ALB with public IP
 - private subnet EC2 Wordpress with private IP
 - private subnet RDS Database with private IP

NB : Ansible gets access to remote machine
 - with a bastion instance in a public subnet
 - or with AWS Systems Manager Session Manager


#### Which AWS resources are we declaring ?

|_name_|_description_|_terraform_|_AWS_|
|:--|:--|:--|:--|
| **AMI** | Pre-configured _Amazon Machine Image_ providing the base Ubuntu OS template. | `data.aws_ami` | [AWS AMI Docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html) |
| **EC2 Instance** | _Amazon Elastic Compute Cloud_ is a virtual compute server hosting the application, containers, and services. | `aws_instance` | [AWS EC2 Docs](https://aws.amazon.com/ec2/) |
| **KMS Key** | Centralized key managenent | `aws_kms_key` | [AWS KMS](https://aws.amazon.com/fr/kms/) |
| **EBS Block Store** | Persistent cloud storage volume attached to the instance acting as its root hard drive (`gp3`). | `root_block_device` | [AWS EBS Docs](https://aws.amazon.com/ebs/) |
| **Elastic IP (EIP)** | Static, persistent public IPv4 address assigned to ensure a fixed endpoint. | `aws_eip` | [AWS EIP Docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html) |
| **VPC** | _Virtual Private Cloud_ : Isolated virtual private network space providing network boundary control. | `aws_vpc` | [AWS VPC Docs](https://aws.amazon.com/vpc/) |
| **Subnet** | A segmented logical partition inside the VPC network to group resources. | `aws_subnet` | [AWS Subnet Docs](https://docs.aws.amazon.com/vpc/latest/userguide/configure-subnets.html) |
| **Internet Gateway** | VPC component enabling bidirectional communication between the network and the public internet. | `aws_internet_gateway` | [AWS IGW Docs](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html) |
| **Route Table** | Set of routing rules determining where network traffic from the subnets is directed. | `aws_route_table` | [AWS Route Table Docs](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html) |
| **Security Group** | Virtual stateful firewall controlling permitted inbound and outbound traffic. | `aws_security_group` | [AWS SG Docs](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html) |
| **VPC Flow Logs** | Feature that captures IP traffic information flowing to and from network interfaces. | `aws_flow_log` | [AWS Flow Logs Docs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html) |
| **CloudWatch Log Group** | Centralized log management and storage service repository for system monitoring data. | `aws_cloudwatch_log_group` | [AWS CloudWatch Logs Docs](https://aws.amazon.com/cloudwatch/) |
| **IAM Role** | Identity with specific permission policies determining what AWS resources can do. | `aws_iam_role` | [AWS IAM Roles Docs](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html) |

#### Security

### Distroless images

All service images are built with apko from Wolfi packages: no shell, no package manager, minimal attack surface. Healthchecks use statically compiled Go binaries from [melange-forge](https://github.com/Kazibuya/melange-forge) instead of shell utilities.

### CVE comparison — official vs custom images

| Service | Official image | CVEs (C/H/M/L) | Custom image | CVEs (C/H/M/L) | Packages |
|:--|:--|:--|:--|:--|:--|
| **Angie** | `docker.angie.software/angie:1.11.6` | 256 (32/111/109/4) | `namichel/angie:1.11.6-amd64` | **0** | 366 → 15 |
| **WordPress** | `wordpress:6.9.4` | 923 (27/150/268/9) | `namichel/wordpress:6.9.4-amd64` | **0** | 273 → 36 |
| **MariaDB** | `mariadb:12.2.2` | 248 (3/37/171/34) | `namichel/mariadb:12.2.2-amd64` | **1\*** | 154 → 41 |
| **phpMyAdmin** | `phpmyadmin:5.2-apache` | 748 (23/131/218/11) | `namichel/phpmyadmin:5.2.3-amd64` | **0** | 284 → 118 |

> \* `CVE-2026-8376` in `perl` (Critical): no fix available upstream, low EPSS (< 0.1%). Perl is a transitive dependency of MariaDB and cannot be removed.

### SBOM

Each image build produces a signed SPDX SBOM via apko, tracking every installed package with its upstream source commit. SBOMs are committed alongside `apko.yaml` files under `melange/`.

### CVE Scanning

A GitHub Actions workflow runs on every push to `main`:

1. **syft** catalogs all packages including Composer/Go dependencies not visible to apko
2. **grype** scans the syft inventory against its CVE database
3. **issue-reporter** (from [melange-forge](https://github.com/Kazibuya/melange-forge)) formats findings as structured GitHub Issues with severity labels (`severity:critical`, `severity:high`, etc.)

### Known false positives & ignored CVEs

Two entries are intentionally ignored in `.grype.yaml` :

**`phpmyadmin` npm package**: grype matches a [known malicious npm package](https://github.com/advisories/GHSA-rpcf-p37j-wm4j) named `phpmyadmin` against our PHP application. These are unrelated — one is a malicious npm package, the other is the legitimate PHP web interface. Ignored by package name + type.

**`GO-2026-5024` in `gosu`**: this CVE affects `NewNTUnicodeString`, a Windows NT API. `gosu` runs exclusively on Linux where this code path is unreachable. Ignored by vulnerability ID + binary location (`/usr/bin/gosu`).

### Secrets

In local development, passwords are stored in `compose/secrets/` (gitignored) and mounted read-only into containers. In production (via Ansible), secrets are injected into a tmpfs mount, never written to disk. Both `docker-entrypoint.sh` scripts support `_FILE` environment variables natively for this purpose.

### Checkov

> Static analysis for Infra As Code

- compares code against security policies


## Services

### Angie

> Reverse proxy. Fork of nginx with extended features

- serves WordPress via FastCGI pass to php-fpm
- serves phpMyAdmin at `/phpmyadmin/`
- exposes Prometheus metrics at `/metrics/`
- exposes status API at `/status/`

### Wordpress

> An open source CMS

NB : There is no official module for Wordpress management. Partly because cli evolves too fast and should be compatible with many php versions

### MariaDB

> An open source fork of MySQL

### PHPMyAdmin

> An administration tool for DB

## Network

### Duck DNS

 - we should reestabish mapping every time the infrastructure is redeployed (AWS generates a new public Elastic IP)

---

# Resources

| Url                   | Kind   | Notes                  |
| :------------------------- | :----- | :--------------------- |
| [Terraform doc](https://developer.hashicorp.com/terraform/docs) | 📔 | |
| [Ansible doc](https://docs.ansible.com/) | 📔 | |
| [Taskfile doc](https://taskfile.dev/docs/guide) | 📔 | |
| [Chainguard doc](https://edu.chainguard.dev/) | 📔 | for Melange and Apko |
| [melange-forge](https://github.com/Kazibuya/melange-forge) | 🌐 | Go binaries for distroless images |
| [Wolfi OS](https://github.com/wolfi-dev/os) | 🌐 | Package repository |
| [Syft](https://github.com/anchore/syft) | 🌐 | SBOM and package cataloging |
| [Grype](https://github.com/anchore/grype) | 🌐 | CVE scanner |
| [Automating IT with Ansible](https://www.educative.io/courses/automating-it-infrastructure-with-ansible) | 📘 | |
| [Infra as Code using Terraform](https://www.educative.io/courses/infrastructure-as-code-using-terraform) | 📘 | |
| [Stephane Robert](https://blog.stephane-robert.info/docs/infra-as-code/gestion-de-configuration/ansible/) | 📘 | Excellent tutorials |
| [Installing WP with Ansible](https://oneuptime.com/blog/post/2026-02-21-ansible-deploy-wordpress-site/view) | 📘 | Tutorial using MySQL setup, PHP-FPM, Nginx, wp-cli. ⚠️ Not the same containerized approach yet useful for wp cli steps |

Resource type

 - 📔 official doc
 - 📘 course
 - 🗒️ cheatsheet, synthesis
 - 🌐 web, article
 - 📽️ video

## AI Usage

- guide setup with a prompt asking to proofcheck our approach and suggest alternatives with pros and cons -> we remain in charge of choosing the next step
- fix and improve terraform variables collection script
- debugging help
- PR review
