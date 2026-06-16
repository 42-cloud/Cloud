Ansible Role: Worpress
=========

Ensure initial configuration and content creation of a WordPress blog. Rely on wp-cli (built-in wordpress custom image)

Requirements
------------

* **ansible version**: `2.15` required for docker modules
* **privileges** : `become: true` is required to configure directories and manage docker
* **testing** : role must launched in `--privileged` mode to allow running docker daemon

Role Variables
--------------

### Modifiable variables 

in `defaults/main.yml` :

#### Project

| Variable | Default | Description |
| :--- | :--- | :--- |
| `wordpress_project_name` | `"cloudone"` | Name of the project (used for volumes and stack identification). |
| `wordpress_domain_name` | `"{{ global_domain_name \| default('cloud1.duckdns.org') }}"` | Global domain used to access the deployed services. |
| `wordpress_project_path` | `"{{ global_project_path \| default('/opt/cloud-1') }}"` | Base root directory for the project on the host system. |
| `wordpress_compose_src` | `"{{ wordpress_project_path }}"` | Source path where the Docker Compose configuration files are orchestrated. |
| `wordpress_docker_cmd` | `"docker"` | Binary command to call for Docker operations. |
| `wordpress_admin_users_list` | `"{{ global_admin_users_list \| default([]) \| list }}"` | List of global administrator users. |
| `wordpress_assets_host_path` | `"{{ wordpress_compose_src }}/wordpress/assets"` | Host directory for storing static asset files (images). |

#### Network and Reverse Proxy (Angie)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `wordpress_expose_http` | `"80"` | Public HTTP port exposed by the Angie reverse proxy. |
| `wordpress_expose_https` | `"443"` | Public HTTPS port exposed by the Angie reverse proxy. |
| `wordpress_angie_container_name` | `"angie"` | Custom container name for the Angie web server/reverse proxy instance. |
| `wordpress_angie_conf_path_host` | `"{{ wordpress_compose_src }}/angie/angie.conf"` | Location of the global Angie configuration file on the host. |
| `wordpress_angie_conf_path_dest` | `"/etc/angie/angie.conf"` | Target mount destination for the Angie configuration inside the container. |
| `wordpress_angie_wp_root` | `"{{ wordpress_wp_dir_path_dest }}"` | Shared container path for serving static frontend web files directly. |

#### Database Configuration (MariaDB)

| Variable | Default | Description |
| :--- | :--- | :--- |
| `wordpress_db_container_name` | `"mariadb"` | Custom container name for the MariaDB instance. |
| `wordpress_db_name` | `"wordpress"` | Name of the relational database created for WordPress. |
| `wordpress_db_user` | `"wp_user"` | Standard non-root database user. |
| `wordpress_db_port` | `3306` | Internal networking listening port for the MariaDB service. |
| `wordpress_db_group` | `"mysql"` | System group assigned to the database processes. |
| `wordpress_db_socket` | `"/run/mysqld/mysqld.sock"` | Location of the Unix socket for local connections. |
| `wordpress_db_innodb_buffer_pool_size` | `"128M"` | Memory allocated to the InnoDB buffer pool. |
| `wordpress_db_mem_limit` | `"512m"` | Hard RAM memory limit for the database container. |
| `wordpress_db_mem_res_limit` | `"256m"` | Soft RAM memory reservation limit for MariaDB. |
| `wordpress_db_validate_cmd` | `""` | Optional command used to validate database health status. |
| `wordpress_db_root_password` | `"{{ global_db_root_password \| default('dev_db_admin_pass_fallback') }}"` | Password for the MariaDB administrative `root` account. |
| `wordpress_db_admin_default_password` | `"{{ global_db_admin_default_password \| default('dev_db_admin_pass_fallback') }}"` | Default administrative fallback password. |
| `wordpress_db_password` | `"{{ global_db_password \| default('dev_db_pass_fallback') }}"` | User password associated with `wordpress_db_user`. |

#### WordPress

| Variable | Default | Description |
| :--- | :--- | :--- |
| `wordpress_wp_container_name` | `"wordpress"` | Custom container name for the WordPress application instance. |
| `wordpress_wp_site_title` | `"{{ inventory_hostname }}"` | WordPress site title (dynamically derived from the Ansible target host). |
| `wordpress_wp_theme` | `"twentytwentythree"` | Default active theme applied during initial provisioning. |
| `wordpress_wp_url` | `"{{ global_wp_siteurl }}"` | Configured target base site URL for the application. |
| `wordpress_wp_dir_path_dest` | `"{{ global_wp_dir \| default('/var/www/html') }}"` | Document root directory inside the WordPress container. |
| `wordpress_wp_uid` | `"{{ wordpress_apko_uid }}"` | UID of the user running the application (aligned with apko layer). |
| `wordpress_wp_gid` | `"{{ wordpress_apko_gid }}"` | GID of the user running the application (aligned with apko layer). |
| `wordpress_wp_mem_limit` | `"256m"` | Hard RAM memory limit for the WordPress application container. |
| `wordpress_wp_mem_res_limit` | `"128m"` | Soft RAM memory reservation limit for the WordPress container. |
| `wordpress_wp_admin_user` | `"wp-admin"` | Username for the initial WordPress administrator account. |
| `wordpress_wp_admin_email` | `"admin@cloud.one"` | Email address bound to the WordPress administrative account. |
| `wordpress_wp_admin_default_password` | `"{{ global_wp_admin_default_password \| default('dev_wp_admin_pass_fallback') }}"` | Default fallback password for the `wp-admin` user. |

### Internal and pivot variables

in `vars/main.yml`

* `wordpress_apko_uid` / `wordpress_apko_gid`: `65532` (Hardened non-root user for container execution).
* `wordpress_wp_cli_exec`: Dynamic execution command wrapping `docker exec` with the specified user to interact with WP-CLI without altering file permissions.

### Secrets and fallbacks

To be overridden via Ansible Vault in production

| Variable | Default | Description |
| :--- | :--- | :--- |
| `wordpress_db_root_password` | `"dev_db_admin_pass_fallback"` | MariaDB root password (deployed securely via `/run/secrets`). |
| `wordpress_db_password` | `"dev_db_pass_fallback"` | Password for the `wp_user` database user. |
| `wordpress_wp_admin_default_password` | `"dev_wp_admin_pass_fallback"` | Password for the default WordPress administrator. |

Dependencies
------------

This role requires : 
- `community.docker` for docker compose and container inspection

Necessary PHP dependencies and WordPress CLI are provided in the custom `wordpress` image.

Architecture and features
----------------

### secrets managements

password are copied to the host with restrictive permissions (`0444` and root ownership) to be mounted via **Docker secrets files**. Thus, they are not visible from within the container as environment variable.

### provisioning mechanism for WordPress

tasks are organized into blocks which can be replayed separately.

- ensuring that the wordpress files and directories are present.
- install a theme (customizable with ``)
- purge default content (pages, posts, ...)
- upload posts and images

must-use plugins are used to display the instance name in main title, and customize styling.

Example Playbook
----------------

```yaml
- hosts: all
  gather_facts: true
  become: true
  roles:
    - name: wordpress
```

License
-------

BSD
