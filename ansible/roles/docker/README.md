Ansible Role: Docker
=========

Install and Configure docker (engine, cli) + docker compose plugin on a Ubuntu Jammy (22.04) host

Requirements
------------

* **privileges** : `become: true` is required to install packages and configure APT
* **testing** : role must launched in `--privileged` mode to allow running docker daemon

Role Variables
--------------

Modifiable variables are in `defaults/main.yml` :

| Variable | Default | Description |
| :--- | :--- | :--- |
| `docker_repo_url` | `https://download.docker.com/linux/ubuntu` | Root URL for official Docker APT repository. |
| `docker_repo_gpg_url` | `https://download.docker.com/linux/ubuntu/gpg` | URL for official GPG key to validate Docker APT repository. |
| `docker_version` | `5:29.5.0-1~ubuntu.22.04~jammy` | `docker-ce` and `docker-ce-cli` version. |
| `docker_compose_version` | `5.1.3-1~ubuntu.22.04~jammy` | `docker-compose-plugin` version. |

Internal variables are in `vars/main.yml` :

* `__docker_gpg_path`: `/etc/apt/keyrings/docker.asc`
* `__docker_repo_config_file_path`: `/etc/apt/sources.list.d/docker.sources` (DEB822 format)
* `__docker_keyrings_path`: `/etc/apt/keyrings`

Dependencies
------------

No external Ansible Galaxy dependency
Required packages are installed through APT:
- `ca-certificates`
- `curl`
- `python3-debian`
- `containerd.io`

Example Playbook
----------------

```yaml
- hosts: all
  gather_facts: true
  become: true
  roles:
    - name: docker
```

License
-------

BSD
