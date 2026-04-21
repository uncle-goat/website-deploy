# Dependency Installation Guide

## Package Manager Detection

Choose the appropriate package manager based on your system distribution:

| Distribution | Package Manager | Detection Command |
|-------------|-----------------|-------------------|
| Ubuntu / Debian | apt | `cat /etc/os-release` |
| CentOS / RHEL | yum / dnf | `cat /etc/os-release` |
| Fedora | dnf | `cat /etc/os-release` |
| Alpine | apk | `cat /etc/os-release` |

```bash
# Auto-detect the package manager
if command -v apt &>/dev/null; then PKG="apt"
elif command -v dnf &>/dev/null; then PKG="dnf"
elif command -v yum &>/dev/null; then PKG="yum"
elif command -v apk &>/dev/null; then PKG="apk"
else echo "Unsupported package manager"; exit 1; fi
```

---

## Docker Installation

### Official Installation Script (Recommended)

```bash
curl -fsSL https://get.docker.com | sh
```

### Manual Installation

```bash
# Ubuntu/Debian
apt update
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### Configuration

```bash
# Add the current user to the docker group (no sudo required)
usermod -aG docker $USER
# Log out and back in for changes to take effect

# Start Docker and enable it on boot
systemctl enable --now docker

# Verify the installation
docker --version
docker compose version
```

### Mirror Acceleration (China)

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
EOF
systemctl daemon-reload && systemctl restart docker
```

---

## Nginx Installation

```bash
# Ubuntu/Debian
apt update && apt install -y nginx

# CentOS/RHEL
yum install -y epel-release && yum install -y nginx

# Start and enable on boot
systemctl enable --now nginx

# Verify
nginx -v
systemctl status nginx
```

---

## Node.js Installation

### Method 1: NodeSource (Recommended, suitable for production environments)

```bash
# Node.js 20.x LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# CentOS/RHEL
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs
```

### Method 2: nvm (Suitable for development environments, supports switching between versions)

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
nvm alias default 20
```

### Verification

```bash
node --version   # v20.x.x
npm --version    # 10.x.x
```

---

## Python Installation

### System Package Installation

```bash
# Ubuntu/Debian
apt update && apt install -y python3 python3-pip python3-venv

# CentOS/RHEL
yum install -y python3 python3-pip
```

### pyenv (Multi-version Management)

```bash
curl https://pyenv.run | bash
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc
source ~/.bashrc
pyenv install 3.12
pyenv global 3.12
```

### Verification

```bash
python3 --version
pip3 --version
```

---

## PHP Installation

```bash
# Ubuntu - Install a specific version via the ondrej PPA
apt install -y software-properties-common
add-apt-repository ppa:ondrej/php
apt update

# Install PHP 8.2 and commonly used extensions
apt install -y php8.2-fpm php8.2-cli php8.2-mysql php8.2-pgsql \
    php8.2-gd php8.2-zip php8.2-curl php8.2-mbstring php8.2-xml

# Verify
php -v
php-fpm8.2 -v
```

---

## Certbot Installation

```bash
# Ubuntu/Debian
apt update && apt install -y certbot python3-certbot-nginx

# CentOS/RHEL
yum install -y epel-release
yum install -y certbot python3-certbot-nginx

# Obtain a certificate
certbot --nginx -d example.com -d www.example.com

# Test automatic renewal
certbot renew --dry-run
```

---

## Firewall Configuration

### ufw (Ubuntu)

```bash
ufw allow OpenSSH
ufw allow 'Nginx Full'    # Includes ports 80 and 443
ufw enable
ufw status
```

### firewalld (CentOS/RHEL)

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
firewall-cmd --list-all
```

---

## Mirror Source Configuration (China)

### npm

```bash
npm config set registry https://registry.npmmirror.com
# Verify
npm config get registry
```

### pip

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
# Or edit ~/.pip/pip.conf
```

### Docker

See the "Mirror Acceleration (China)" section in the Docker installation chapter above.

### Composer (PHP)

```bash
composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/
```

### apt (Ubuntu)

```bash
sed -i 's|archive.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list
sed -i 's|security.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list
apt update
```

### yum (CentOS)

```bash
sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-*.repo
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://mirrors.aliyun.com|g' /etc/yum.repos.d/CentOS-*.repo
yum makecache
```
