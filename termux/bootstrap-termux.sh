#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# Termux 一键环境部署脚本 —— CloudFlare-ip 优选工具 持久化运行
# -----------------------------------------------------------------------------
# 用法：
#   chmod +x termux/bootstrap-termux.sh
#   ./termux/bootstrap-termux.sh
#
# 作用：
#   1. 安装 Python / git / curl / tmux / cronie / termux-api 等依赖
#   2. 建立 Python 虚拟环境并安装 requirements
#   3. 获取唤醒锁，配置 Termux 后台运行环境
#   4. 安装 supervisor.sh（守护 + 循环）、boot 自启、crond 定时任务
# =============================================================================
set -e

# ---- 颜色 ----
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; N='\033[0m'
info() { echo -e "${G}[+]${N} $*"; }
warn() { echo -e "${Y}[!]${N} $*"; }
err()  { echo -e "${R}[x]${N} $*"; }

# ---- 定位项目根目录（本脚本位于 <root>/termux/ 下）----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"
info "项目目录: $PROJECT_DIR"

# =============================================================================
# 0. 前置检查
# =============================================================================
if [ ! -d "/data/data/com.termux" ]; then
    err "当前不是 Termux 环境（未检测到 /data/data/com.termux）。"
    err "请在 Termux 中运行本脚本。"
    exit 1
fi

if [ -z "$PREFIX" ]; then
    err "环境变量 \$PREFIX 未设置，Termux 环境异常。"
    exit 1
fi

# =============================================================================
# 1. 安装系统依赖
# =============================================================================
info "更新 pkg 索引..."
pkg update -y

info "安装依赖包 (python git curl tmux cronie termux-api openssl)..."
pkg install -y python git curl tmux cronie termux-api openssl libffi clang

# termux-services 可选（提供 sv 服务管理），失败不阻断
pkg install -y termux-services || warn "termux-services 安装失败，忽略。"

# =============================================================================
# 2. Python 虚拟环境 + 依赖
# =============================================================================
VENV_DIR="$PROJECT_DIR/.venv"
if [ ! -d "$VENV_DIR" ]; then
    info "创建虚拟环境: $VENV_DIR"
    python -m venv "$VENV_DIR"
else
    info "虚拟环境已存在，跳过创建。"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

info "升级 pip / wheel..."
pip install --upgrade pip wheel setuptools

if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    info "安装 requirements.txt..."
    pip install -r "$PROJECT_DIR/requirements.txt"
else
    warn "未找到 requirements.txt，安装默认依赖 (curl_cffi aiohttp requests)..."
    pip install curl_cffi aiohttp requests
fi

info "Python 依赖安装完成。"

# =============================================================================
# 3. 唤醒锁 + 后台运行环境
# =============================================================================
info "获取唤醒锁（防止 CPU 休眠）..."
termux-wake-lock || warn "termux-wake-lock 失败，请确认已安装 Termux:API 应用。"

# =============================================================================
# 4. Termux:Boot 开机自启
# =============================================================================
BOOT_DIR="$HOME/.termux/boot"
mkdir -p "$BOOT_DIR"
cat > "$BOOT_DIR/00-cloudflare-ip.sh" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
# Termux:Boot 开机自启 —— 启动 CloudFlare-ip 守护进程
termux-wake-lock
sleep 20
tmux new-session -d -s cfip "$PROJECT_DIR/termux/supervisor.sh"
EOF
chmod +x "$BOOT_DIR/00-cloudflare-ip.sh"
info "已安装开机自启脚本: $BOOT_DIR/00-cloudflare-ip.sh"

# =============================================================================
# 5. crontab 定时任务（每天凌晨 4 点清理旧日志，防止塞满存储）
# =============================================================================
CRON_LINE="0 4 * * * find $PROJECT_DIR/termux/logs -name '*.log' -mtime +7 -delete"
if command -v crontab >/dev/null 2>&1; then
    ( crontab -l 2>/dev/null | grep -v "termux/logs" ; echo "$CRON_LINE" ) | crontab -
    info "已配置日志清理定时任务（保留 7 天）。"
fi

# =============================================================================
# 6. Phantom Process Killer 提醒
# =============================================================================
warn "==========================================================="
warn "重要：Android 12+ 请务必关闭 Phantom Process Killer！"
warn "无 root / 用电脑 adb 执行："
warn "  adb shell settings put global settings_enable_monitor_phantom_procs false"
warn "否则进程跑一会儿会被系统批量杀掉。"
warn "==========================================================="

info "环境部署完成！"
echo
info "下一步："
echo "  1) 编辑 config.json 填入你的配置（Cloudflare Token / GitHub 等）"
echo "  2) 编辑 git_sync.sh 填入 github_token / username / repo / branch"
echo "  3) 启动:   ./termux/supervisor.sh   （或开机自启）"
echo "  4) 查看:   tmux attach -t cfip    |    日志: termux/logs/"
