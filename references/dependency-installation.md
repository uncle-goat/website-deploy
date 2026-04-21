# 依赖安装指南

## 包管理器检测

根据系统发行版选择对应的包管理器：

| 发行版 | 包管理器 | 检测命令 |
|--------|----------|----------|
| Ubuntu / Debian | apt | `cat /etc/os-release` |
| CentOS / RHEL | yum / dnf | `cat /etc/os-release` |
| Fedora | dnf | `cat /etc/os-release` |
| Alpine | apk | `cat /etc/os-release` |

```bash
# 自动检测包管理器
if command -v apt &>/dev/null; then PKG="apt"
elif command -v dnf &>/dev/null; then PKG="dnf"
elif command -v yum &>/dev/null; then PKG="yum"
elif command -v apk &>/dev/null; then PKG="apk"
else echo "Unsupported package manager"; exit 1; fi
```

---

## Docker 安装

### 官方安装脚本（推荐）

```bash
curl -fsSL https://get.docker.com | sh
```

### 手动安装

```bash
# Ubuntu/Debian
apt update
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 配置

```bash
# 将当前用户加入 docker 组（免 sudo）
usermod -aG docker $USER
# 重新登录后生效

# 启动并设置开机自启
systemctl enable --now docker

# 验证安装
docker --version
docker compose version
```

### 国内镜像加速

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

## Nginx 安装

```bash
# Ubuntu/Debian
apt update && apt install -y nginx

# CentOS/RHEL
yum install -y epel-release && yum install -y nginx

# 启动并设置开机自启
systemctl enable --now nginx

# 验证
nginx -v
systemctl status nginx
```

---

## Node.js 安装

### 方式一：NodeSource（推荐，适合生产环境）

```bash
# Node.js 20.x LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# CentOS/RHEL
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs
```

### 方式二：nvm（适合开发环境，支持多版本切换）

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
nvm alias default 20
```

### 验证

```bash
node --version   # v20.x.x
npm --version    # 10.x.x
```

---

## Python 安装

### 系统包安装

```bash
# Ubuntu/Debian
apt update && apt install -y python3 python3-pip python3-venv

# CentOS/RHEL
yum install -y python3 python3-pip
```

### pyenv（多版本管理）

```bash
curl https://pyenv.run | bash
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc
source ~/.bashrc
pyenv install 3.12
pyenv global 3.12
```

### 验证

```bash
python3 --version
pip3 --version
```

---

## PHP 安装

```bash
# Ubuntu - 通过 ondrej PPA 安装指定版本
apt install -y software-properties-common
add-apt-repository ppa:ondrej/php
apt update

# 安装 PHP 8.2 及常用扩展
apt install -y php8.2-fpm php8.2-cli php8.2-mysql php8.2-pgsql \
    php8.2-gd php8.2-zip php8.2-curl php8.2-mbstring php8.2-xml

# 验证
php -v
php-fpm8.2 -v
```

---

## Certbot 安装

```bash
# Ubuntu/Debian
apt update && apt install -y certbot python3-certbot-nginx

# CentOS/RHEL
yum install -y epel-release
yum install -y certbot python3-certbot-nginx

# 获取证书
certbot --nginx -d example.com -d www.example.com

# 测试自动续期
certbot renew --dry-run
```

---

## 防火墙配置

### ufw（Ubuntu）

```bash
ufw allow OpenSSH
ufw allow 'Nginx Full'    # 包含 80 和 443 端口
ufw enable
ufw status
```

### firewalld（CentOS/RHEL）

```bash
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
firewall-cmd --list-all
```

---

## 国内镜像源配置

### npm

```bash
npm config set registry https://registry.npmmirror.com
# 验证
npm config get registry
```

### pip

```bash
pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
# 或编辑 ~/.pip/pip.conf
```

### Docker

见上方 Docker 安装章节的「国内镜像加速」部分。

### Composer（PHP）

```bash
composer config -g repo.packagist composer https://mirrors.aliyun.com/composer/
```

### apt（Ubuntu）

```bash
sed -i 's|archive.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list
sed -i 's|security.ubuntu.com|mirrors.aliyun.com|g' /etc/apt/sources.list
apt update
```

### yum（CentOS）

```bash
sed -i 's|mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-*.repo
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://mirrors.aliyun.com|g' /etc/yum.repos.d/CentOS-*.repo
yum makecache
```
