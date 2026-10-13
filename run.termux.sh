#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# CloudFlare-ip 持久化守护 (Termux 版)
# -----------------------------------------------------------------------------
# 运行策略：对齐「系统时间的固定刻度」，默认每 1.5 小时一个刻度。
#
#   以本地时间每天 00:00:00 为原点，刻度依次为
#   00:00 / 01:30 / 03:00 / 04:30 / 06:00 / 07:30 / 09:00 …
#   每到一个刻度就跑一轮。例如 00:37 启动 → 等到 01:30 才跑第一轮。
#
#   - 刻度间隔 = 5400 秒（1.5h），可用环境变量 CFIP_INTERVAL 覆盖
#     （例如 CFIP_INTERVAL=3600 → 每整点；7200 → 每两小时）
#   - 等待期间重启守护，重算后仍是同一个刻度 → 绝不会提前推送
#   - 倒计时每秒刷新同一行，attach 进去能看到实时跳动
#   - 显式 TMUX_TMPDIR，避免 socket 分裂导致会话无法管理
#   - wakelock / main.py 崩溃后仍继续 / 日志轮转
# =============================================================================

export TMUX_TMPDIR="$HOME/.tmux-cfnb"
mkdir -p "$TMUX_TMPDIR"
export PATH="$PREFIX/bin:$PATH"
cd "$(dirname "$0")" || exit 1
PROJECT_DIR="$(pwd)"

LIVE="cron.log"
HIST="cron-history.log"

# ---- 刻度间隔：默认 1.5 小时（5400 秒）----
INTERVAL="${CFIP_INTERVAL:-5400}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LIVE"
}

# ---- 获取唤醒锁（Termux:API 未装时静默失败）----
if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock 2>/dev/null || true
    log "尝试获取唤醒锁"
fi

# 把秒数格式化成 "1h 23m 45s"
fmt_dur() {
    local t="$1"
    printf '%dh %02dm %02ds' $((t / 3600)) $(((t % 3600) / 60)) $((t % 60))
}

# 计算「下一个刻度」的 Unix 时间戳：
#   以「本地当天 00:00:00」为原点，每 INTERVAL 秒一个刻度，
#   取严格大于 NOW 的最小刻度。
#   这样刻度在本地时间上呈现为 00:00 / 01:30 / 03:00 / 04:30 …（默认 1.5h）
next_slot() {
    local now="$1"
    local day0
    day0=$(date -d "$(date '+%Y-%m-%d') 00:00:00" +%s 2>/dev/null)
    if [ -z "$day0" ]; then
        # 兜底：万一 date -d 不可用，退化为 epoch 对齐
        echo "$(( (now / INTERVAL + 1) * INTERVAL ))"
        return
    fi
    local off=$(( now - day0 ))
    # 处理夏令时/时区跳变导致的负偏移
    [ "$off" -lt 0 ] && off=0
    local k=$(( off / INTERVAL + 1 ))
    echo $(( day0 + k * INTERVAL ))
}

# 实时倒计时：每秒刷新一行，attach 里可见秒级跳动
#   $1 = 需要等待的总秒数
#   $2 = 目标刻度的时间戳（用于显示固定时刻）
countdown() {
    local remain="$1"
    local target="$2"
    while [ "$remain" -gt 0 ]; do
        printf '\r⏳ 距下一轮还有 %s  （下一轮 %s）   ' \
            "$(fmt_dur "$remain")" \
            "$(date -d "@$target" '+%m-%d %H:%M:%S' 2>/dev/null || date '+%H:%M:%S')"
        sleep 1
        # 每秒用剩余量递减，同时用目标刻度校正漂移
        remain=$(( target - $(date +%s) ))
        [ "$remain" -lt 0 ] && remain=0
    done
    printf '\r\033[K'   # 清掉倒计时行
}

RUN=0
NOW=$(date +%s)
SLOT=$(next_slot "$NOW")
WAIT=$((SLOT - NOW))

log "守护进程启动，项目目录: $PROJECT_DIR，刻度间隔 ${INTERVAL}s"
log "当前 $(date '+%F %T')，下一刻度 $(date -d "@$SLOT" '+%F %T')，需等待 ${WAIT}s"

while true; do
    if [ "$WAIT" -gt 0 ]; then
        echo "[$(date '+%F %T')] 等待 $(fmt_dur "$WAIT") 到刻度 $(date -d "@$SLOT" '+%m-%d %H:%M:%S')"
        countdown "$WAIT" "$SLOT"
    fi

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

    # 下一轮：再次对齐到下一个刻度
    NOW=$(date +%s)
    SLOT=$(next_slot "$NOW")
    WAIT=$((SLOT - NOW))
done
