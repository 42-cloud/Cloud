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

#### Roles

|Role|Responsabilities|
|:-- |:--|
|`host_bootstrap`|OS preparation, SSH config, UFW config, create directories for data persistence with appropriate permissions|
|`docker`|generic role to install daemon and docker compose|
|`wordpress_app`|centralized role for stack management : would be too difficult to manage 2 different roles for wordpress and db|


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
- PR review