CFIP_TMUX_TMPDIR="$HOME/.tmux-cfnb"
export TMUX_TMPDIR="$CFIP_TMUX_TMPDIR"
mkdir -p "$TMUX_TMPDIR"

SESS="cfnb"
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
  attach)
    exec tmux attach -t "$SESS" ;;
  phantom)
    settings get global settings_enable_monitor_phantom_procs 2>&1 ;;
  *)
    echo "用法: $0 {start|stop|restart|status|log|attach|phantom}"
    exit 1 ;;
esac