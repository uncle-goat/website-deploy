# Environment Detection Guide

This document describes the output fields of `detect-environment.sh` and how they are used in deployment decisions.

## Detection Items

### os -- Operating System Information

| Field | Description |
|-------|-------------|
| name | Distribution name (Ubuntu / CentOS / Debian / Alpine, etc.) |
| version | Major version number |
| arch | Architecture (x86_64 / aarch64) |

**Decision impact:** Different distributions use different package managers (apt / yum / apk), which affects the generated dependency installation commands. The `arch` field determines whether Docker images for the corresponding architecture can be pulled.

### resources -- Hardware Resources

| Field | Description |
|-------|-------------|
| cpu_cores | Number of CPU cores |
| memory_mb | Available memory (MB) |
| disk_free_gb | Free disk space (GB) |

**Minimum resource requirements:**

| Deployment Method | Minimum Memory | Minimum Disk |
|-------------------|----------------|--------------|
| Docker Deployment | 2 GB | 10 GB |
| Full Server Deployment | 1 GB | 5 GB |
| Static Site | 512 MB | 1 GB |
| CMS (WordPress) | 2 GB | 20 GB |

When resources are insufficient, prompt the user with scaling recommendations instead of forcing the deployment.

### docker -- Docker Environment

| Field | Description |
|-------|-------------|
| installed | Whether Docker is installed |
| version | Docker Engine version |
| compose_version | Docker Compose version |
| daemon_running | Whether the daemon is running |

**Version requirements:** Docker Engine >= 20.10, Compose >= 2.0. Prompt for an upgrade if the version is too old.

### nginx -- Nginx

| Field | Description |
|-------|-------------|
| installed | Whether Nginx is installed |
| version | Nginx version |

When Nginx is available, prefer reusing it to avoid duplicate installations. It is used for reverse proxying and static file serving.

### Runtime Environments

Detects whether the following runtimes are installed and their versions: `nodejs`, `python`, `php`, `go`, `java`.

**Common framework version requirements quick reference:**

| Framework | Runtime | Minimum Version |
|-----------|---------|-----------------|
| Next.js / Nuxt | Node.js | 18.x |
| Django / Flask | Python | 3.9 |
| WordPress / Laravel | PHP | 8.1 |
| Hugo | Go | 1.20 |
| Spring Boot | Java | 17 |

### ports_in_use -- Ports in Use

Lists the ports currently being listened on. Before deployment, you must check whether the target ports (default 80/443) conflict. If there is a conflict, the occupying process must be terminated or the port must be changed.

### ssh -- SSH Configuration

| Field | Description |
|-------|-------------|
| configured | Whether SSH is configured |
| key_files | List of available key files |

Used in remote deployment scenarios. When key files are available, `deploy-ssh.sh` can be called directly.

### firewall -- Firewall Status

| Field | Description |
|-------|-------------|
| type | Firewall type (ufw / iptables / firewalld) |
| status | Whether the firewall is enabled |
| open_ports | List of allowed ports |

Web services require ports 80 (HTTP) and 443 (HTTPS) to be reachable. If the firewall is enabled but these ports are not allowed, prompt the user to open them.

### is_container -- Whether Running Inside a Container

Boolean value. Inside a container, `systemd` is typically unavailable, which affects the choice of service management method (use `supervisord` or run in the foreground instead).

### current_user / has_sudo -- Permission Context

| Field | Description |
|-------|-------------|
| current_user | Current username |
| has_sudo | Whether the user has sudo privileges |

Without sudo privileges, system packages cannot be installed and ports 80/443 cannot be bound. The user should be informed in advance.

---

## Environment Type Classification Logic

Based on detection results, the environment is automatically classified to determine the deployment strategy:

```
if ssh.configured AND target_is_remote:
    → Remote SSH (use deploy-ssh.sh for remote deployment)

elif docker.installed AND docker.daemon_running:
    → Docker-ready (prefer Docker / Compose deployment)

elif any([nginx, nodejs, python, php, go, java]) installed:
    → Bare-metal with tools (tools already available, install dependencies and deploy directly)

else:
    → Fresh server (full installation required, install runtime first then deploy)
```

**Priority:** Remote SSH > Docker > Existing Tools > Fresh Installation.

---

## Common Issues

### Docker installed but daemon not running

```bash
sudo systemctl start docker
sudo systemctl enable docker   # Start on boot
```

### Insufficient permissions (Permission denied)

```bash
# Add user to the docker group to use docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

### Port already in use

```bash
# Check which process is using the port
sudo lsof -i :80
# Terminate the process or change the deployment port
```

### Insufficient disk space

```bash
docker system prune -a   # Clean up unused images and containers
sudo apt autoremove -y   # Clean up system package cache
```

### Insufficient memory

```bash
# Create a 2GB swap file
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
# Persist: append to the end of /etc/fstab
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```
