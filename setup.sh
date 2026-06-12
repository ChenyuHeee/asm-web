#!/bin/bash
# ============================================
# ASM Web 实验平台 — 一键安装脚本
# 目标: Ubuntu 22.04
# ============================================
set -e

echo "=== ASM Web 安装脚本 ==="

# ---- 系统依赖 ----
echo "[1/5] 安装系统依赖..."
sudo apt update
sudo apt install -y jwasm dosbox xvfb python3-pip python3-venv nginx

# JWasm 可能不在官方源，如果安装失败则从源码编译
if ! command -v jwasm &>/dev/null; then
    echo "JWasm 未找到，从源码编译..."
    sudo apt install -y gcc make git
    git clone --depth 1 https://github.com/Baron-von-Riedesel/JWasm.git /tmp/jwasm-build
    cd /tmp/jwasm-build
    make -f Makefile.Linux -j$(nproc)
    sudo cp jwasm /usr/local/bin/
    cd /tmp
    rm -rf /tmp/jwasm-build
fi

if ! command -v dosbox &>/dev/null; then
    echo "dosbox 未找到，尝试安装 dosbox-staging..."
    sudo apt install -y dosbox-staging
    # 如果 dosbox-staging 的命令不同，创建软链接
    if ! command -v dosbox &>/dev/null && command -v dosbox-staging &>/dev/null; then
        sudo ln -sf "$(command -v dosbox-staging)" /usr/bin/dosbox
    fi
fi

echo "工具检查:"
echo "  jwasm:  $(command -v jwasm || echo '未找到!')"
echo "  dosbox: $(command -v dosbox || echo '未找到!')"
echo "  xvfb-run: $(command -v xvfb-run || echo '未找到!')"

# ---- Python 环境 ----
echo "[2/5] 配置 Python 虚拟环境..."
PROJECT_DIR="/opt/asm-web"
sudo mkdir -p "$PROJECT_DIR"
sudo chown "$USER:$USER" "$PROJECT_DIR"
python3 -m venv "$PROJECT_DIR/venv"
source "$PROJECT_DIR/venv/bin/activate"
pip install flask gunicorn

# ---- 部署代码 ----
echo "[3/5] 部署代码..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp -r "$SCRIPT_DIR/backend/"* "$PROJECT_DIR/"
mkdir -p /tmp/asm-web
chmod 755 /tmp/asm-web

# ---- systemd 服务 ----
echo "[4/5] 配置 systemd 服务..."
sudo tee /etc/systemd/system/asm-web.service > /dev/null <<EOF
[Unit]
Description=ASM Web Experiment Platform
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/gunicorn -w 2 -b 127.0.0.1:5000 app:app
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable asm-web
sudo systemctl restart asm-web

# ---- Nginx ----
echo "[5/5] 配置 Nginx..."
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_IP")
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

echo ""
echo "=== 安装完成! ==="
echo "访问地址: http://$PUBLIC_IP"
echo ""
echo "测试编译:"
echo "  echo 'code segment' > /tmp/test.asm"
echo "  echo 'assume cs:code' >> /tmp/test.asm"
echo "  echo 'main: mov ah,4ch; int 21h' >> /tmp/test.asm"
echo "  echo 'code ends' >> /tmp/test.asm"
echo "  echo 'end main' >> /tmp/test.asm"
echo "  jwasm -mz -nologo /tmp/test.asm"
echo ""
echo "日志: sudo journalctl -u asm-web -f"
