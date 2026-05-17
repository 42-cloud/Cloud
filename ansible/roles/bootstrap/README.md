Ansible Role: Bootstrap
======================

Prepare and secure the host system prior to deploying application services:

- manage UFW firewall configuration
- create directories with proper permissions for Docker volumes

Requirements
------------

* **Ansible** minimum version: `2.15` (recommended for variable typing and idempotency).
* **Privileges**: `become: true` is required to manage UFW and modify system directory ownership (`owner/group`).
* **Required Collection**: `community.general` (provides the `community.general.ufw` module).

Role Variables
--------------

Configurable variables for defining paths and permissions of persistent volumes are located in `defaults/main.yml`:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `bootstrap_db_dir` | `/var/lib/mysql_data` | database persistent directory mountpoint |
| `bootstrap_db_uid` | `999` | UID for the directory owner (`999` is the common one for `mysql` user of MariaDB). |
| `bootstrap_db_gid` | `999` | GID for the directory group. |
| `bootstrap_wp_dir` | `/var/www/html` | wordpress directory mountpoint |
| `bootstrap_wp_uid` | `33` | UID for the directory owner (`33` for `www-data` in the official WordPress container). |
| `bootstrap_wp_gid` | `33` | GID for the directory group. |

*Note: Allowed UFW ports (`22`, `80`, `443`) and default filtering policies are hardcoded within the tasks to ensure strict adherence to the project's security guidelines.*

Dependencies
------------

No external dependencies on other Ansible roles.

This role automatically installs the following system package via APT:
* `ufw`

Example Playbook
----------------

### Standard Usage

```yaml
- hosts: all
  gather_facts: true
  become: true
  roles:
    - name: bootstrap
```

License
-------

BSD
