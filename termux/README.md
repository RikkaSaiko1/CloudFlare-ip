# Termux 持久化运行指南（Android）

在手机 Termux 里让本项目**长期无人值守运行**：开机自启、整点自动跑、崩溃自动拉起、日志自动轮转。

> ⚠️ 本目录下的脚本仅适用于 **Termux (Android)**。Windows / Linux 服务器请直接用手动 `python main.py` 或系统 crontab。

---

## 1. 工作原理

```
Termux:Boot（开机）
   └─ ~/.termux/boot/start-cfnb.sh
        └─ tmux new-session -d -s cfnb ./run.termux.sh
             └─ run.termux.sh
                  ├─ termux-wake-lock      防止休眠
                  ├─ sleep 到下一个整点      与「每小时更新」对齐
                  ├─ python main.py        单轮优选（自带 flock 防重入）
                  ├─ tee cron.log / cron-history.log
                  └─ 回到第二步，无限循环
```

关键点：`main.py` **跑完一轮就退出**，所以"持续运行"由外层脚本负责；
`run.termux.sh` 又跑在 tmux 会话里，SSH 断开 / Termux 通知被划掉都不会中断。

### 1.1 socket 路径必须显式指定（重要）

如果直接 `tmux new -d`，Termux:Boot 启动的服务和手动打开的终端会解析到**不同的 socket 目录**，表现为：

- `tmux ls` 说 `no server running`
- `tmux attach` 找不到会话
- 杀不掉、重启不了，只能留一堆孤儿进程

因此本方案统一使用固定目录：

```bash
export TMUX_TMPDIR="$HOME/.tmux-cfnb"   # socket = ~/.tmux-cfnb/tmux-<uid>/default
```

`run.termux.sh` 和 `~/.termux/boot/start-cfnb.sh` 里都已写死，**任何终端里都能直接管理**。

---

## 2. 安装

### 2.1 安装依赖应用（从 F-Droid，不要用 Play 版）

| 应用 | 作用 | 缺失后果 |
|---|---|---|
| [Termux:Boot](https://f-droid.org/packages/com.termux.boot/) | 开机自动执行 `~/.termux/boot/` 下的脚本 | 手机重启后不会自动跑 |
| [Termux:API](https://f-droid.org/packages/com.termux.api/) | 提供 `termux-wake-lock` 等命令 | Doze 休眠后进程可能被挂起 |

装完 Termux:API 后还需执行一次：

```bash
pkg install termux-api
```

### 2.2 关闭系统对后台进程的限制

在 Termux 里执行（只读当前值，通常已够用）：

```bash
settings get global settings_enable_monitor_phantom_procs
```

如需彻底关闭 Android 的幻影进程查杀，**必须在 PC 上通过 adb 执行**（Termux 内会报 SecurityException）：

```bash
adb shell settings put global settings_enable_monitor_phantom_procs false
```

再把 Termux 的电池策略设为「无限制」，并允许自启动、锁定最近任务卡片。

### 2.3 一键初始化（可选）

```bash
cd ~/CloudFlare-ip
bash termux/bootstrap-termux.sh
```

它会：安装/更新依赖包、创建 venv、写入 `~/.termux/boot/start-cfnb.sh`、立即启动守护。
**已经手动配好环境的可以跳过这步。**

---

## 3. 日常管理

```bash
cd ~/CloudFlare-ip
./ctl.sh            # 无参数时打印用法

./ctl.sh start      # 启动守护
./ctl.sh stop       # 停止守护
./ctl.sh restart    # 重启守护
./ctl.sh status     # 会话 + 进程状态
./ctl.sh log 50     # 看 cron.log 最近 50 行
./ctl.sh attach     # 进入会话看实时输出（Ctrl-b 再按 d 退出）
./ctl.sh phantom    # 查看幻影进程查杀开关当前值
```

`ctl.sh` 在仓库根目录，也复制了一份到 `termux/ctl.sh`（内容相同，任选其一）。

---

## 4. 日志

| 文件 | 内容 | 清理策略 |
|---|---|---|
| `cron.log` | 本轮运行详情，**每轮开始前清空** | 只保留最新一轮 |
| `cron-history.log` | 所有轮次追加，含 `===== 第 N 轮开始/结束 =====` 标记 | 超过 10 MB 时截断只留最后 5 MB |

看最近一轮结果：

```bash
./ctl.sh log
```

看历史轮次：

```bash
grep -aE '轮开始|轮结束|已自动推送' cron-history.log | tail
```

---

## 4.4 生成运行命令清单（`/generate-run-commands`）

改完 `config.json` 后，想让程序**按当前配置**吐一份可直接复制的命令清单：

```bash
# 需要 Node.js >= 16（Termux: pkg install nodejs）
node scripts/generate-run-commands.js            # 写入 RUN-COMMANDS.md
node scripts/generate-run-commands.js --stdout   # 只打印，不写文件
node scripts/generate-run-commands.js --json     # 只输出配置摘要
node scripts/generate-run-commands.js -o my.md   # 指定输出路径
```

或用 npm（若装了 Node）：

```bash
npm run generate-run-commands          # 写文件
npm run run-commands                   # 打印到终端
npm run run-commands:json              # 摘要 JSON
```

生成内容包含：当前配置摘要表 + Termux / Linux / Windows 三种平台的可复制命令 + 校验排障命令。
`config.json` 不存在时会退回内置默认值并给出提示；文件损坏时以退出码 1 报错。

> 纯可选步骤：它只**读**配置生成文档，不改变任何运行状态。

---

## 4.5 从零部署（全新克隆仓库）

`config.json` 与 `git_sync.sh` 已被 `.gitignore` 排除，**全新 clone 下来是没有的**。
不补上它们，脚本虽然能跑（`main.py` 缺 `config.json` 时会退回内置默认值），但你**自己调过的优选参数会全部丢失**，且 `sync_to_github()` 找不到同步脚本会跳过推送。

先补配置（必需）：

```bash
cd ~/CloudFlare-ip
cp /path/to/your/backup/config.json   ./config.json
cp /path/to/your/backup/git_sync.sh   ./git_sync.sh
chmod +x git_sync.sh
```

没有备份时，直接让程序生成一份默认配置，再按需修改：

```bash
cd ~/CloudFlare-ip
python main.py          # 首轮会提示「未找到配置文件…将使用内置默认配置运行」
# 或手动创建
cat > config.json <<'JSON'
{}
JSON
```

`git_sync.sh` 至少要改 4 处，否则推送必然失败：

```bash
github_token="你的_PAT"        # 需 repo 写权限
github_username="你的用户名"
repo_name="你的仓库名"
branch="main"
```

再起守护：

```bash
./ctl.sh start
./ctl.sh status
```

> 已验证：`git_sync.sh` 只执行 `git add ip.txt`，不会把你带 token 的配置文件提交出去。

---

## 5. 自定义运行间隔

默认整点运行。改间隔只需在 `run.termux.sh` 里把等待秒数的算法换掉，或用 `supervisor.sh`：

```bash
# 每 30 分钟跑一轮，崩溃后自动重启（指数退避 1s → 900s）
CFIP_INTERVAL=1800 bash termux/supervisor.sh &
```

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `CFIP_INTERVAL` | `3600` | 两轮之间的间隔（秒） |
| `CFIP_START_DELAY` | `0` | 首次启动前等待（秒） |
| `CFIP_MIN_BACKOFF` | `1` | 崩溃重试最小间隔（秒） |
| `CFIP_MAX_BACKOFF` | `900` | 崩溃重试最大间隔（秒） |

---

## 6. 卸载 / 回滚

```bash
cd ~/CloudFlare-ip
./ctl.sh stop
rm -f ~/.termux/boot/start-cfnb.sh        # 取消开机自启
rm -rf ~/.tmux-cfnb                       # 清掉 socket 目录
# 原有 run.sh 已备份为 run.sh.bak-<日期>，需要时改回来即可
```

---

## 7. 常见问题

**Q：`tmux ls` 提示 `no server running on .../default`？**
A：当前 shell 没设 `TMUX_TMPDIR`。用 `./ctl.sh` 管理，或先 `export TMUX_TMPDIR="$HOME/.tmux-cfnb"`。

**Q：日志里一直停在"正在请求数据源"？**
A：手机网络出口被数据源站点风控，等等或换 Wi-Fi；脚本有 3 次重试。

**Q：出现了两个 `run.termux.sh` 进程？**
A：`main.py` 自带 flock，并发只会让后一个立刻退出，不会重复推送；但仍建议只留一个守护会话。

**Q：手机重启后没自动跑？**
A：确认装了 Termux:Boot（F-Droid 版），且 `~/.termux/boot/start-cfnb.sh` 有可执行权限；部分国产 ROM 需要在系统设置里给 Termux「自启动」权限。
