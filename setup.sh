#!/bin/bash
# ============================================
# ASM Web 实验平台 — 一键安装脚本
# 目标: Ubuntu 22.04
# ============================================
set -e

echo "=== ASM Web 安装脚本 ==="

# ---- 创建专用系统用户 ----
if ! id -u asm-web &>/dev/null; then
    sudo useradd --system --no-create-home --shell /usr/sbin/nologin asm-web
fi

# ---- 系统依赖 ----
echo "[1/5] 安装系统依赖..."
sudo apt update
sudo apt install -y dosbox xvfb python3-pip python3-venv nginx curl

# JWasm 从源码编译（官方源中不包含 jwasm 包）
if ! command -v jwasm &>/dev/null; then
    echo "JWasm 未找到，从源码编译..."
    sudo apt install -y gcc make git
    git clone --depth 1 https://github.com/Baron-von-Riedesel/JWasm.git /tmp/jwasm-build
    cd /tmp/jwasm-build
    make -f GccUnix.mak -j$(nproc)
    sudo cp build/GccUnixR/jwasm /usr/local/bin/
    cd /tmp
    rm -rf /tmp/jwasm-build
fi

if ! command -v dosbox &>/dev/null; then
    echo "警告: dosbox 未安装。请手动安装: sudo apt install dosbox"
fi

echo "工具检查:"
echo "  jwasm:  $(command -v jwasm || echo '未找到!')"
echo "  dosbox: $(command -v dosbox || echo '未找到!')"
echo "  xvfb-run: $(command -v xvfb-run || echo '未找到!')"

# ---- 部署代码 ----
echo "[2/5] 部署代码..."
PROJECT_DIR="/opt/asm-web"
sudo mkdir -p "$PROJECT_DIR"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
sudo cp -r "$SCRIPT_DIR/backend/"* "$PROJECT_DIR/"

# ---- Python 环境 ----
echo "[3/5] 配置 Python 虚拟环境..."
sudo python3 -m venv "$PROJECT_DIR/venv"
sudo "$PROJECT_DIR/venv/bin/pip" install -r "$PROJECT_DIR/requirements.txt"

# 设置归属和权限
sudo chown -R asm-web:asm-web "$PROJECT_DIR"
sudo chmod 755 "$PROJECT_DIR"

# 临时目录
sudo mkdir -p /tmp/asm-web
sudo chown asm-web:asm-web /tmp/asm-web
sudo chmod 755 /tmp/asm-web

# tmpfiles.d 自动清理（超过 1 小时的临时文件）
sudo tee /etc/tmpfiles.d/asm-web.conf > /dev/null <<'EOF'
d /tmp/asm-web 0755 asm-web asm-web 1h
EOF

# ---- systemd 服务 ----
echo "[4/5] 配置 systemd 服务..."
sudo tee /etc/systemd/system/asm-web.service > /dev/null <<EOF
[Unit]
Description=ASM Web Experiment Platform
After=network.target

[Service]
Type=simple
User=asm-web
Group=asm-web
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/gunicorn -w 2 -b 127.0.0.1:5000 app:app
Restart=on-failure
RestartSec=3
PrivateTmp=true
NoNewPrivileges=true
ProtectHome=true
ReadWritePaths=/tmp/asm-web
ReadOnlyPaths=$PROJECT_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable asm-web
sudo systemctl restart asm-web

# ---- Nginx ----
echo "[5/5] 配置 Nginx..."
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || wget -qO- ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
sudo tee /etc/nginx/sites-available/asm-web > /dev/null <<EOF
server {
    listen 80;
    server_name $PUBLIC_IP;

    client_max_body_size 1m;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 30s;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/asm-web /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

# ---- 防火墙 ----
sudo ufw allow 80/tcp
sudo ufw --force enable

echo ""
echo "=== 安装完成! ==="
echo "访问地址: http://$PUBLIC_IP"
echo ""
echo "验证安装成功。日志: sudo journalctl -u asm-web -f"
