# Pre-Deploy Checklist

## Environment Check

- [ ] OS version is compatible (Ubuntu 20.04+ / Debian 11+ / CentOS 8+)
- [ ] Sufficient disk space (Docker deployment: 10GB+, server deployment: 5GB+, CMS system: 20GB+)
- [ ] Sufficient memory (Docker deployment: 2GB+, server deployment: 1GB+, CMS system: 2GB+)
- [ ] Required ports are not in use (80, 443, 3000, 3306, 5432, 6379, 8080, etc.)
- [ ] Firewall has opened necessary ports (80, 443)
- [ ] Current user has sudo privileges (if package installation is needed)

## Project Check

- [ ] Build command succeeds locally (`npm run build` / `python setup.py`, etc.)
- [ ] All environment variables are prepared (`.env` file or `.env.example` template)
- [ ] No sensitive information is hardcoded in code (API keys, passwords, tokens)
- [ ] `.gitignore` includes `.env`, `node_modules`, `__pycache__`, `.venv`, etc.
- [ ] Database migration scripts are prepared and tested
- [ ] Dependency versions are locked (`package-lock.json`, `pnpm-lock.yaml`, `requirements.txt`)
- [ ] No debug code in the codebase (`console.log`, `debugger`, `print` debug statements)
- [ ] Production environment configuration is separated from development

## Network Check

- [ ] Domain DNS resolves to the server IP (if using a domain)
- [ ] SSL certificate can be obtained (port 80 is accessible, DNS is in effect)
- [ ] Server is accessible via SSH (for remote deployment)
- [ ] Server security group/firewall rules are configured

## Docker-Specific Check

- [ ] Docker Engine 20.10+ is installed
- [ ] Docker Compose 2.0+ is installed
- [ ] Docker daemon is running (`systemctl status docker`)
- [ ] `.dockerignore` file has been created (excluding `.git`, `node_modules`, `.env`, etc.)
- [ ] Docker image build passes local testing
- [ ] Inter-container network communication is configured correctly

## Server-Specific Check

- [ ] Nginx is installed or can be installed (`nginx -v`)
- [ ] Node.js / Python / PHP versions match project requirements
- [ ] systemd is available (non-container environments)
- [ ] Log directory has been created with write permissions
- [ ] Application runtime user has been created (do not run the application as root)
