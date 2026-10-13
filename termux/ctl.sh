#!/data/data/com.termux/files/usr/bin/bash
# CloudFlare-ip 守护控制脚本 (Termux)
# 用法: ./ctl.sh {start|stop|restart|status|log|next|attach|phantom}
CFIP_TMUX_TMPDIR="$HOME/.tmux-cfnb"
export TMUX_TMPDIR="$CFIP_TMUX_TMPDIR"
mkdir -p "$TMUX_TMPDIR"

SESS="cfnb"
INTERVAL="${CFIP_INTERVAL:-5400}"

# 计算下一个刻度（与 run.termux.sh 保持一致）
next_slot() {
    local now="$1" day0
    day0=$(date -d "$(date '+%Y-%m-%d') 00:00:00" +%s 2>/dev/null) || {
        echo "$(( (now / INTERVAL + 1) * INTERVAL ))"; return; }
    local off=$(( now - day0 )); [ "$off" -lt 0 ] && off=0
    echo $(( day0 + (off / INTERVAL + 1) * INTERVAL ))
}

case "${1:-}" in
  start)
    tmux has-session -t "$SESS" 2>/dev/null && { echo "已在运行"; exit 0; }
    tmux new-session -d -s "$SESS" "./run.termux.sh"
    echo "已启动"; tmux ls ;;
  stop)
    tmux kill-session -t "$SESS" 2>/dev/null && echo "已停止" || echo "未在运行" ;;
  restart)
    tmux kill-session -t "$SESS" 2>/dev/null; sleep 1
    tmux new-session -d -s "$SESS" "./run.termux.sh"; echo "已重启"; tmux ls ;;
  status)
    tmux ls 2>&1
    echo "--- run.termux.sh 进程 ---"
    ps -ef | grep run.termux.sh | grep -v grep ;;
  log)
    tail -n "${2:-40}" cron.log ;;
  next)
    NOW=$(date +%s); SLOT=$(next_slot "$NOW")
    printf '当前时间  : %s\n' "$(date '+%F %H:%M:%S')"
    printf '刻度间隔  : %ss\n' "$INTERVAL"
    printf '下一轮时间: %s （还有 %ds）\n' \
        "$(date -d "@$SLOT" '+%F %H:%M:%S')" $((SLOT - NOW)) ;;
  attach)
    exec tmux attach -t "$SESS" ;;
  phantom)
    settings get global settings_enable_monitor_phantom_procs 2>&1 ;;
  *)
    echo "用法: $0 {start|stop|restart|status|log|next|attach|phantom}"
    exit 1 ;;
esac
