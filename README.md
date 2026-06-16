# Overview

Automated deployment of Wordpress related services using Terraform and Ansible

[![CI/CD Pipeline](https://github.com/42-cloud/Cloud/actions/workflows/security.yml/badge.svg)](https://github.com/42-cloud/Cloud/actions)

[![CI/CD Pipeline](https://github.com/42-cloud/Cloud/actions/workflows/ansible.yml/badge.svg)](https://github.com/42-cloud/Cloud/actions)

# Tasks list

__network and security__
- [ ] only `80` and `443` should be accessible (replace 8080 and 8443)
- [ ] usage of TLS between load balancer and instances ?
- [x] network isolation of DB from the internet

__roles__
- [ ] Bootstrap role
  - [x] Readme
  - [x] Molecule tests
- [ ] LB role
  - [ ] Readme
  - [ ] Molecule tests
- [x] Docker role
  - [x] Readme
  - [x] Molecule tests
- [ ] Wordpress role
  - [x] Readme for `wordpress` role
  - [x] Molecule tests
  - [x] handler to reload angie
  - [ ] PHP My Admin configuration

__resilience__
- [ ] dynamic DNS : call DuckDNS GET API to attach LB IP to subdomain
- [ ] auto-restart if server is rebooted with data preserved

__scalability__
- [x] parallel deploy to multiple servers

__flexibility__
- [-] provider-agnostic configuration
  - [x] provider-independant load balancer 
- [-] can create various users with admin rights on EC2, app admin rights on wordpress

__security__
- [x] distroless OCI images via apko/melange
- [x] SBOM generation for all images
- [x] automated CVE scanning via syft + grype
- [x] GitHub Issues automation for CVE reporting
- [x] secrets via file (tmpfs in prod)
- [x] non-root containers
- [ ] GHA release for melange-forge binaries
- [ ] matrix refactor for CVE scan workflow
- [ ] pinpoint images in docker compose (no `latest`)

__styling__

- [ ] yaml lint
- [ ] ansible lint

---

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
pip install ansible-core
ln -sf $HOME/.ansible_venv/bin/ansible $HOME/bin/ansible
ln -sf $HOME/.ansible_venv/bin/ansible-playbook $HOME/bin/ansible-playbook
deactivate

# generate ansible vault password
openssl rand -base64 32  > .vault_pass_cloudone

# add other local analysis and linting dependencies
pip install checkov argcomplete

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

### domain and terraform vars

Go on `duckdns.org`, choose an available custom subdomain (ex: `cloud1`).
Encrypt your duckdns token : 

```bash
ansible-vault encrypt_string \
  --vault-id=cloudone \
  --name 'global_duckdns_token' <DUCKDNS_TOKEN>
```

and replace the corresponding value in `ansible/group_vars/all/all.yml`

```bash
# create terraform/terraform.tfvars
task tf:tfvars
```

fill required inputs

### provisionning and configuration

```bash
# download providers
task tf:init

# check terraform project correctness
task tf:plan

# deploy infrastructure
task tf:apply

# deploy configuration
task ansible:play

```

Access the app on `https://cloud1.duckdns.org` (supposing you chose `cloud1`)

### replay a role or a group of tasks

```bash
task ansible:tag TAG=angie-lb
```

---

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

## Architecture evolution

We didn't have a definite idea of the target architecture when starting the project. It served as a sandbox to experiment with different approaches.

The architecture went through different phases:

```bash
[Internet] ---> [Elastic IP] ---> [EC2 Instance: Angie + WP + MariaDB]
```

- _instances_ : each computing instance is directly accessible. Security is ensured by rootless containerization, and by splitting docker networks between a web-accessible one, and another. We went on adding an elastic IP for each instance and mapping it to a DuckDNS domain. It seemed a good choice, but didn't allow to scale easily if we wanted to maintain the DuckDNS mapping, as there is a max limit of 5 subdomains per account.

```bash
[Internet] ---> [AWS ALB] ---> [Private Subnet: EC2 Instances (WP)]
                                      |---> [AWS KMS / CloudWatch Logs]
```

- _instances with Amazon load balancer_ : we added an instance of Amazon Load Balancer, which was aimed at being the only public access point, while instances IP would have been private. Yet, atop of being even-more provider-dependent and costly (billed by the hour), it increased the size and complexity of terraform state declaration, as we had to declare subnets, security groups, targets groups. Meanwhile, we had also added new AWS resources (IAM policies, KMS, logging) to patch potential security flaws highlighted by Checkov. 

- _instances with custom made load balancer_ : this implied having a separate instance with Angie as a load balancer. Network security is ensured at OS level by iptable configuration. Contrary to free version of Nginx, Angie handles ACME challenges, which also enabled us to get a LetsEncrypt certificate for the chosen subdomain. On the minus side, availability level is not the same as ALB, and scaling would require configuration modification through Ansible.

Would we have had more time to explore more in-depth cloud architecture, it could have been relevant to have 
- fully multitier instances with separate DBs (Amazon RDS)
- shared storage for WordPress uploads (Amazon EFS)
- duplication across availability zones
- isolate PhPMyAdmin on its own subnet and instance
- other services such as caching to improve performance.
- ...

### Which AWS resources are we declaring ?

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
- exposes status API at `/status/`
- exposes Prometheus metrics at `/metrics/` (in local deploy)

### Wordpress

> An open source CMS

NB : There is no official Ansible module for Wordpress management. Partly because cli evolves too fast and should be compatible with many php versions.

### MariaDB

> An open source fork of MySQL

### PHPMyAdmin

> An administration tool for DB

## Network

### Duck DNS

> A DNS provider

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

| Goal                   | Tool   |
| :--------------------- | :----- |
| **Senior guidance** : we submit an approach, the AI suggests alternative implementations with their tradeoffs. | LLM Chatbot (Gemini, Claude) |
| **Documentation / Crash course** : we ask for a recap over a tools or part of its features. | LLM Chatbot (Gemini, Claude) |
| **Boilerplate code** : we asked to generate parts of the code, that were not in the immediate scope of the project and/or once we reckoned we would have been able to do it by ourselves : useed for `tfvars.sh` script | Chatbot (Gemini, Claude) |
| **Debugging help** : sometimes direct questions (why does this occur + console log as a context). Many times. But as we got a better mastery of the concepts and tools, we tried to prompt the AI to provide methods and heuristics instead | 
| **PR Review** : | Github Copilot | 

We didn't take time to provide a recurrent context for this project, although the quality and rapidity of AI inputs could have largely benefitted from it.

We used a browser extension (PiiBlocker) to prevent leaking personal information.

---

# Challenges met and lessons learned

The subject provided by 42 holds within 1 page. The goal is simple : at first glance, we _merely_ have to automate the deployment of the Inception project, which is part of common core. Yet it is easy to turn it into something bigger than expected:

- many new domains to understand from the subject itself (cloud, devops) each with its concepts and ecosystem
- one group member is already experienced with supply chain security. It is a very hot topic, so we were both eager to delve on this and make use of Chainguard and other CI tools. We (especially namichel) put extra efforts in generating ad hoc images for the project. A PR 
- assimilating the information can prove difficult : Ansible alone has more than 3000 module. Some other tools are less documented. We used AI models to skim through documentation, while being aware that they can easily hallucinate about the specifications.