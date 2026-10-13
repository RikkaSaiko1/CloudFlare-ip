#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# CloudFlare-ip 守护进程 (supervisor)
# -----------------------------------------------------------------------------
# 职责：
#   1. 获取 Termux 唤醒锁，防止 CPU 休眠
#   2. 循环运行 main.py（main.py 本身是「跑一次就退出」的，因此由本脚本负责间隔循环）
#   3. main.py 崩溃时自动重启（带退避，避免疯狂重启）
#   4. 全部输出写入按日期分割的日志文件
#
# 用法：
#   ./termux/supervisor.sh                # 前台运行（建议放进 tmux）
#   tmux new-session -d -s cfip ./termux/supervisor.sh   # 后台常驻
#   停止: tmux kill-session -t cfip
# =============================================================================

# ---- 路径定位 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR" || exit 1

# ---- 可调参数（也可用环境变量覆盖）----
INTERVAL="${CFIP_INTERVAL:-3600}"     # 每轮之间的间隔秒数（默认 1 小时）
START_DELAY="${CFIP_START_DELAY:-30}" # 启动前等待（等网络就绪）
MAX_BACKOFF="${CFIP_MAX_BACKOFF:-900}"  # 崩溃后最大退避秒数（15 分钟）
MIN_BACKOFF="${CFIP_MIN_BACKOFF:-30}" # 崩溃后初始退避秒数

# ---- 日志 ----
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/supervisor.log"
APP_LOG="$LOG_DIR/main-$(date '+%Y%m%d').log"

# ---- 环境 ----
export PATH="$PREFIX/bin:$PATH"

log() {
    # 带时间戳写入 supervisor 日志并同时输出到终端
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ---- 唤醒锁 ----
acquire_lock() {
    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null && log "已获取唤醒锁 (termux-wake-lock)" \
            || log "警告: termux-wake-lock 执行失败，请确认已安装 Termux:API"
    else
        log "警告: 未安装 termux-api，无法获取唤醒锁（CPU 可能休眠）"
    fi
}

# ---- 寻找 Python 解释器（优先虚拟环境）----
find_python() {
    if [ -x "$PROJECT_DIR/.venv/bin/python" ]; then
        echo "$PROJECT_DIR/.venv/bin/python"
    elif command -v python >/dev/null 2>&1; then
        command -v python
    elif command -v python3 >/dev/null 2>&1; then
        command -v python3
    else
        echo ""
    fi
}

# ---- 退出时释放唤醒锁 ----
cleanup() {
    log "收到退出信号，正在释放唤醒锁..."
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null || true
    exit 0
}
trap cleanup SIGTERM SIGINT SIGHUP

# =============================================================================
# 主循环
# =============================================================================
log "=========================================="
log "CloudFlare-ip 守护进程启动"
log "项目目录 : $PROJECT_DIR"
log "轮询间隔 : ${INTERVAL}s"
log "APP 日志 : $APP_LOG"
log "=========================================="

acquire_lock

PYTHON="$(find_python)"
if [ -z "$PYTHON" ]; then
    log "致命错误: 未找到 Python 解释器。请先运行 termux/bootstrap-termux.sh"
    exit 1
fi
log "使用 Python: $PYTHON"

if [ ! -f "$PROJECT_DIR/main.py" ]; then
    log "致命错误: 未找到 main.py"
    exit 1
fi

log "等待 ${START_DELAY}s 让网络/系统就绪..."
sleep "$START_DELAY"

backoff="$MIN_BACKOFF"
round=0

while true; do
    round=$((round + 1))
    start_ts=$(date '+%Y-%m-%d %H:%M:%S')
    log "----- 第 $round 轮开始 @ $start_ts -----"

    # 每轮重新获取唤醒锁（系统可能在休眠后丢失）
    acquire_lock

    # 运行 main.py，输出同时写终端和当日 APP 日志
    "$PYTHON" "$PROJECT_DIR/main.py" 2>&1 | tee -a "$APP_LOG"
    exit_code=${PIPESTATUS[0]}

    end_ts=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$exit_code" -eq 0 ]; then
        log "第 $round 轮完成 @ $end_ts (exit=0)，等待 ${INTERVAL}s 后进入下一轮。"
        backoff="$MIN_BACKOFF"   # 正常完成，重置退避
        sleep "$INTERVAL"
    else
        log "第 $round 轮异常退出 @ $end_ts (exit=$exit_code)，${backoff}s 后重启。"
        sleep "$backoff"
        # 指数退避，上限 MAX_BACKOFF
        backoff=$(( backoff * 2 ))
        [ "$backoff" -gt "$MAX_BACKOFF" ] && backoff="$MAX_BACKOFF"
    fi

    # 日志轮转：只清理超过 7 天的 main-*.log
    find "$LOG_DIR" -name 'main-*.log' -mtime +7 -delete 2>/dev/null || true
done
