# Overview

Automated deployment of Wordpress related services using Terraform and Ansible

# Setup

## Prerequisites

```bash
sh -c "$(curl -ssL https://taskfile.dev/install.sh)" -- -d -b $HOME/bin
```

## Tasks

```bash
# create terraform/terraform.tfvars
task tfvars

# download providers
task init

# check terraform project correctneess
task plan

# deploy
task apply

```


# Resources

| Url                   | Kind   | Notes                  |
| :------------------------- | :----- | :--------------------- |
| [Terraform doc](https://developer.hashicorp.com/terraform/docs) | 📔 | |
| [Ansible doc](https://docs.ansible.com/) | 📔 | |
| [Automating IT with Ansible](https://www.educative.io/courses/automating-it-infrastructure-with-ansible) | 📘 | |
| [Infra as Code using Terraform](https://www.educative.io/courses/infrastructure-as-code-using-terraform) | 📘 | |

Resource type

 - 📔 official doc
 - 📘 course
 - 🗒️ cheatsheet, synthesis
 - 🌐 web, article
 - 📽️ video

## AI Usage

- fix and improve script
- PR review