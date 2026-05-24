# Overview

Automated deployment of Wordpress related services using Terraform and Ansible

# Setup

## Prerequisites

```bash
sh -c "$(curl -sSL https://taskfile.dev/install.sh)" -- -d -b $HOME/bin
```

## Tasks

```bash
# create terraform/terraform.tfvars
task tfvars

# download providers
task init

# check terraform project correctness
task plan

# deploy
task apply

```


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

- used as a base layer for Angie
- quickly updated in case of CVE
- compatible with packages compiled for glibc

### Melange

> Declarative APK builder : compiles packages from source code

### Apko

> Image assembler : assembles packages into a _distroless_ image

- **secure** : images don't have shell, reducing attack surface
- **idempotent** : images are identical
- **lightweight**

APKO generates: 
- SPDX with all components and licences for each package
- _SBOM_ (software bill of materials) which can be used to audit supply chain

UID and GID are `65532` : conventional ID for non-root

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

#### Security rules

Some Checkov lints that we fixed:

| *code* | *category* | *should* | *should not*|
|:--:|:--:|:--|:--|
|CKV_AWS_8|security|encrypt storage volumes by default|-|
|CKV2_AWS_11|auditability|capture in/out IP trafic from VPC with a `aws_flow_log` instance|-|
|CKV_AWS_12|networking|default security group should explicitely block by default|-|
|CKV_AWS_23|observability|`description` field for rule of security group|undocumented rules|
|CKV2_AWS_41|security|instance should use an IAM profile|should not store AWS access keys|
|CKV_AWS_79|security|metadata should be secured against SSRF with a token => IMDSv2|no INDSv1 which use classic HTTP GET|
|CKV_AWS_130|networking|assign private IP by default. Necessity of public IP can be mitigated in different ways (see architecture)|no public IP by default|
|CKV_AWS_135|performance|instance should have a dedicated bandwidth to EBS volumes|do not share disk traffic with standard network traffic|
|CKV_AWS_158|security|encrypt logs|-|
|CKV_AWS_382|networking|outgoing trafic rules should be restricted to necessary protocols|no `-1` (all protocols) on `0.0.0.0`|
|CKV2_ANSIBLE_1|use HTTPS in module calls (ex `uri`)|-|


Some others that we ignored: 
| *code* | *category* | *should* | *should not* | *tradeoff* |
|:--:|:--:|:--|:--|:--|
|CKV_AWS_126|observability|should rely on frequent checks (every 1 mn)||billed by cloud provider|

### Ansible

> An agentless configuration management tool

#### Variables

- 3 levels of variables
  - group_vars
  - vars (within a role)
  - default (within a role) : allow to reuse group_vars as they have a lower priority than them, contrary to vars

#### TDD with molecules

- a *test_sequence* can have many steps, among which main ones:
  - create
  - converge
  - verify
  - destroy

**adapting tests to dockerized test environment**
- molecule runs tests in docker container. For `docker` role, we have distinct tasks whether the environment is prod or test:
  - in test env, we are within a container with no `systemd`. Therefore, we use `ansible.builtin.shell` to look for / launch `dockerd` process
  - prod relies on `ansible.builtin.service` module
- similarly, test assertion rely on command `docker info`

#### Roles

|Role|Responsibilities|
|:-- |:--|
|`bootstrap`|OS preparation, SSH config, UFW config, create directories for data persistence with appropriate permissions|
|`docker`|generic role to install daemon and docker compose|
|`wordpress`|centralized role for stack management : would be too difficult to manage 2 different roles for wordpress and db|


## Security

### Checkov

> Static analysis for Infra As Code

- compares code against security policies

## Services

### Angie

> Reverse proxy. Fork of nginx with extended features



---

# Resources

| Url                   | Kind   | Notes                  |
| :------------------------- | :----- | :--------------------- |
| [Terraform doc](https://developer.hashicorp.com/terraform/docs) | 📔 | |
| [Ansible doc](https://docs.ansible.com/) | 📔 | |
| [Taskfile doc](https://taskfile.dev/docs/guide) | 📔 | |
| [Chainguard doc](https://edu.chainguard.dev/) | 📔 | for Melange and Apko |
| [Automating IT with Ansible](https://www.educative.io/courses/automating-it-infrastructure-with-ansible) | 📘 | |
| [Infra as Code using Terraform](https://www.educative.io/courses/infrastructure-as-code-using-terraform) | 📘 | |
| [Stephane Robert](https://blog.stephane-robert.info/docs/infra-as-code/gestion-de-configuration/ansible/) | 📘 | Excellent tutorials |

Resource type

 - 📔 official doc
 - 📘 course
 - 🗒️ cheatsheet, synthesis
 - 🌐 web, article
 - 📽️ video

## AI Usage

- fix and improve script
- guide setup with a prompt asking to proofcheck our approach and suggest alternatives with pros and cons -> we remain in charge of choosing the next step
- PR review