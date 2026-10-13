#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# CloudFlare-ip 持久化守护 (Termux 版)
# -----------------------------------------------------------------------------
# 特性：
#   - 显式 TMUX_TMPDIR，避免 socket 分裂导致会话无法管理
#   - 对齐整点运行（与 README 声明的「每小时更新一次」一致）
#   - wakelock / main.py 崩溃后仍继续 / 日志轮转
# =============================================================================

export TMUX_TMPDIR="$HOME/.tmux-cfnb"
mkdir -p "$TMUX_TMPDIR"
export PATH="$PREFIX/bin:$PATH"
cd "$(dirname "$0")" || exit 1
PROJECT_DIR="$(pwd)"

LIVE="cron.log"
HIST="cron-history.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LIVE"
}

# ---- 获取唤醒锁（Termux:API 未装时静默失败）----
if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null || true
    log "尝试获取唤醒锁"
fi

RUN=0
log "守护进程启动，项目目录: $PROJECT_DIR"

while true; do
    # 对齐到下一个整点
    m=$((10#$(date +%M))); s=$((10#$(date +%S)))
    w=$(( (60 - m) * 60 - s ))
    [ "$w" -le 0 ] && w=3600

    log "等待 $w 秒到下一个整点..."
    sleep "$w"

    RUN=$((RUN + 1))
    : > "$LIVE"
    echo "===== 第 $RUN 轮开始 $(date '+%F %T') =====" | tee -a "$LIVE" "$HIST"

    python main.py 2>&1 | tee -a "$LIVE" "$HIST"

    echo "===== 第 $RUN 轮结束 $(date '+%F %T') =====" | tee -a "$LIVE" "$HIST"

    # 历史日志超 10MB 时只保留最后 5MB
    if [ "$(wc -c < "$HIST" 2>/dev/null || echo 0)" -gt 10485760 ]; then
        tail -c 5242880 "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
        log "cron-history.log 超限，已轮转"
    fi
done
