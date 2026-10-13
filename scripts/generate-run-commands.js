#!/usr/bin/env node
/**
 * generate-run-commands.js
 * ---------------------------------------------------------------------------
 * 对应斜杠命令: /generate-run-commands
 *
 * 读取仓库中的 config.json，生成一份「可直接复制粘贴运行」的命令清单，
 * 覆盖 Termux / Linux / Windows / 前台调试 四种场景，并附带各平台的
 * 部署与排障命令。
 *
 * 用法:
 *   node scripts/generate-run-commands.js
 *   node scripts/generate-run-commands.js --out RUN-COMMANDS.md
 *   node scripts/generate-run-commands.js --json          # 只输出结构，不写文件
 *   node scripts/generate-run-commands.js --stdout        # 打印 Markdown 而不写文件
 *
 * 退出码:
 *   0  成功（config.json 存在且可解析）
 *   0  成功（config.json 缺失，已用内置默认值并给出警告）
 *   1  config.json 存在但 JSON 损坏
 * ---------------------------------------------------------------------------
 */

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CONFIG_FILE = path.join(ROOT, 'config.json');

// ========================= 内置默认配置 =========================
// 与 main.py 的 defaults 保持一致，仅取生成命令所需的字段。
const DEFAULTS = {
  USE_GLOBAL_MODE: true,
  GLOBAL_TOP_N: 3,
  PER_COUNTRY_TOP_N: 3,
  BANDWIDTH_CANDIDATES: 200,
  TCP_PROBES: 5,
  MIN_SUCCESS_RATE: 0.9,
  TIMEOUT: 5,
  PROGRESS_PRINT_INTERVAL: 100,
  FILTER_COUNTRIES_ENABLED: false,
  ALLOWED_COUNTRIES: ['JP', 'SG', 'HK', 'TW', 'US', 'KR', 'MY', 'TH', 'VN', 'PH'],
  PRE_FILTER_BLOCKED_ENABLED: true,
  PRE_FILTER_BLOCKED_COUNTRIES: ['CN'],
  PRE_FILTER_PORT_ENABLED: true,
  PRE_FILTER_PORTS: [443, 8443, 2053, 2083, 2087, 2096],
  ENABLE_LOGGING: true,
  LOG_FILE: 'run.log',
  ENABLE_WXPUSHER: false,
  ENABLE_CLOUDFLARE_DNS_UPDATE: false,
};

// ========================= 命令行参数 =========================
function parseArgs(argv) {
  const opts = { out: null, json: false, stdout: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--out' || a === '-o') {
      opts.out = argv[++i];
    } else if (a === '--json') {
      opts.json = true;
    } else if (a === '--stdout') {
      opts.stdout = true;
    } else if (a === '--help' || a === '-h') {
      opts.help = true;
    }
  }
  return opts;
}

// ========================= 读取配置 =========================
function loadConfig() {
  const notes = [];
  let cfg;
  if (!fs.existsSync(CONFIG_FILE)) {
    notes.push('未找到 config.json，已使用内置默认配置。');
    cfg = Object.assign({}, DEFAULTS);
  } else {
    const raw = fs.readFileSync(CONFIG_FILE, 'utf8');
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      console.error(`[错误] config.json 解析失败: ${e.message}`);
      process.exit(1);
    }
    cfg = Object.assign({}, DEFAULTS);
    for (const key of Object.keys(DEFAULTS)) {
      if (parsed[key] !== undefined) cfg[key] = parsed[key];
      else notes.push(`配置项 ${key} 缺失，使用默认值。`);
    }
  }
  return { cfg, notes };
}

// ========================= 摘要构建 =========================
function buildSummary(cfg) {
  const mode = cfg.USE_GLOBAL_MODE
    ? `全局最优 ${cfg.GLOBAL_TOP_N} 个`
    : `每国家最优 ${cfg.PER_COUNTRY_TOP_N} 个`;

  const ports = Array.isArray(cfg.PRE_FILTER_PORTS) ? cfg.PRE_FILTER_PORTS : [];
  const blocked = Array.isArray(cfg.PRE_FILTER_BLOCKED_COUNTRIES)
    ? cfg.PRE_FILTER_BLOCKED_COUNTRIES.join(', ')
    : String(cfg.PRE_FILTER_BLOCKED_COUNTRIES || '');

  return {
    mode,
    tcpProbes: cfg.TCP_PROBES,
    minSuccessRate: `${Math.round(cfg.MIN_SUCCESS_RATE * 100)}%`,
    timeout: cfg.TIMEOUT,
    progressInterval: cfg.PROGRESS_PRINT_INTERVAL,
    bandwidthCandidates: cfg.BANDWIDTH_CANDIDATES,
    loginEnabled: cfg.FILTER_COUNTRIES_ENABLED,
    allowed: Array.isArray(cfg.ALLOWED_COUNTRIES)
      ? cfg.ALLOWED_COUNTRIES.join(', ')
      : String(cfg.ALLOWED_COUNTRIES || ''),
    preFilterBlocked: cfg.PRE_FILTER_BLOCKED_ENABLED ? `启用（${blocked}）` : '禁用',
    preFilterPort: cfg.PRE_FILTER_PORT_ENABLED
      ? `启用（仅 ${ports.join(', ')}）`
      : '禁用',
    logging: cfg.ENABLE_LOGGING ? `启用（${cfg.LOG_FILE}）` : '禁用',
    wxpusher: cfg.ENABLE_WXPUSHER ? '启用' : '禁用',
    dnsUpdate: cfg.ENABLE_CLOUDFLARE_DNS_UPDATE ? '启用' : '禁用',
  };
}

// ========================= Markdown 生成 =========================
function fence(lang, code) {
  return '```' + lang + '\n' + code.replace(/\s+$/, '') + '\n```';
}

function generateMarkdown(cfg, notes) {
  const s = buildSummary(cfg);
  const L = [];

  L.push('# 🚀 运行命令速查（自动生成）');
  L.push('');
  L.push(`> 由 \`scripts/generate-run-commands.js\` 依据 \`config.json\` 生成于 ${new Date().toISOString().replace('T', ' ').slice(0, 19)}`);
  L.push('> 不要手改本文件；改完 `config.json` 后重新运行生成命令即可。');
  L.push('');

  if (notes.length) {
    L.push('> [!NOTE]');
    notes.slice(0, 8).forEach((n) => L.push(`> - ${n}`));
    L.push('');
  }

  // ---- 配置摘要 ----
  L.push('## 1. 本次配置摘要');
  L.push('');
  L.push('| 项目 | 取值 |');
  L.push('| --- | --- |');
  L.push(`| 优选模式 | ${s.mode} |`);
  L.push(`| 每节点 TCP 探测次数 | ${s.tcpProbes} |`);
  L.push(`| 最低成功率 | ${s.minSuccessRate} |`);
  L.push(`| 超时 | ${s.timeout} |`);
  L.push(`| 进度打印间隔 | ${s.progressInterval} |`);
  L.push(`| 带宽测速候选数 | ${s.bandwidthCandidates} |`);
  L.push(`| 白名单过滤 | ${s.loginEnabled ? `启用（${s.allowed}）` : `禁用（${s.allowed}）`} |`);
  L.push(`| 前置黑名单 | ${s.preFilterBlocked} |`);
  L.push(`| 前置端口过滤 | ${s.preFilterPort} |`);
  L.push(`| 日志 | ${s.logging} |`);
  L.push(`| WxPusher 通知 | ${s.wxpusher} |`);
  L.push(`| Cloudflare DNS 更新 | ${s.dnsUpdate} |`);
  L.push('');

  // ---- 0. 准备 ----
  L.push('## 2. 通用准备（所有平台）');
  L.push('');
  L.push('```bash');
  L.push('git clone https://github.com/<you>/CloudFlare-ip.git');
  L.push('cd CloudFlare-ip');
  L.push('```');
  L.push('');
  L.push('> `config.json` 与 `git_sync.sh` 已被 `.gitignore` 排除，全新克隆后需自行补齐。');
  L.push('');

  // ---- 1. Termux ----
  L.push('## 3. Termux（Android 持久化）');
  L.push('');
  L.push('**首次部署：**');
  L.push('');
  L.push(fence('bash', [
    'pkg update -y && pkg upgrade -y',
    'pkg install -y python git curl tmux termux-api',
    'cd ~/CloudFlare-ip',
    '',
    '# 补齐被 gitignore 的配置文件',
    'cp /path/to/config.json   ./config.json',
    'cp /path/to/git_sync.sh   ./git_sync.sh',
    'chmod +x git_sync.sh run.termux.sh ctl.sh',
    '',
    '# 可选：一键环境初始化（装依赖 + 写开机自启 + 启动守护）',
    'bash termux/bootstrap-termux.sh',
  ].join('\n')));
  L.push('');
  L.push('**日常管理：**');
  L.push('');
  L.push(fence('bash', [
    'cd ~/CloudFlare-ip',
    './ctl.sh start      # 启动守护（幂等）',
    './ctl.sh status     # 会话 + 进程状态',
    './ctl.sh log 50     # 最近 50 行 cron.log',
    './ctl.sh attach     # 进入实时输出（Ctrl-b 再按 d 退出）',
    './ctl.sh restart    # 重启',
    './ctl.sh stop       # 停止',
  ].join('\n')));
  L.push('');
  L.push('**不开守护、只要跑一轮：**');
  L.push('');
  L.push(fence('bash', [
    'cd ~/CloudFlare-ip',
    'python main.py 2>&1 | tee cron.log',
  ].join('\n')));
  L.push('');

  // ---- 2. Linux ----
  L.push('## 4. Linux 服务器');
  L.push('');
  L.push('**前台跑一轮（调参用）：**');
  L.push('');
  L.push(fence('bash', [
    'cd ~/CloudFlare-ip',
    'python3 -m venv .venv && source .venv/bin/activate',
    'pip install -r requirements.txt',
    'python3 main.py',
  ].join('\n')));
  L.push('');
  L.push('**一键部署（写 crontab，每 5 分钟整点对齐）：**');
  L.push('');
  L.push(fence('bash', [
    'chmod +x setup.sh',
    'sudo ./setup.sh          # 需要装系统包时用 sudo',
  ].join('\n')));
  L.push('');
  L.push('**手写 crontab（每小时，整点）：**');
  L.push('');
  L.push(fence('bash', [
    '(crontab -l 2>/dev/null; \\',
    '  echo "0 * * * * cd $HOME/CloudFlare-ip && /usr/bin/python3 main.py >> $HOME/CloudFlare-ip/cron.log 2>&1") | crontab -',
    'crontab -l               # 确认已写入',
    'tail -f cron.log         # 看日志',
  ].join('\n')));
  L.push('');
  L.push('> `main.py` 自带 flock 单实例锁（`.run.lock`），即使两次重叠启动也只会有一个真正执行。');
  L.push('');

  // ---- 3. Windows ----
  L.push('## 5. Windows（PowerShell）');
  L.push('');
  L.push('**前台跑一轮：**');
  L.push('');
  L.push(fence('powershell', [
    'cd "F:\\vscode main\\CloudFlare-ip"',
    'python -m venv .venv',
    '.\\.venv\\Scripts\\Activate.ps1',
    'pip install -r requirements.txt',
    'python main.py',
  ].join('\n')));
  L.push('');
  L.push('**一键部署（注册计划任务，每 5 分钟）：**');
  L.push('');
  L.push(fence('powershell', [
    'cd "F:\\vscode main\\CloudFlare-ip"',
    '.\\setup.ps1',
  ].join('\n')));
  L.push('');

  // ---- 4. 排障 ----
  L.push('## 6. 校验与排障');
  L.push('');
  L.push(fence('bash', [
    '# 1) 校验语法（不实际运行）',
    'python -m py_compile main.py && echo "main.py 语法 OK"',
    '',
    '# 2) 确认依赖齐全',
    "python -c \"import requests, aiohttp; print('core deps OK')\"",
    "python -c \"import curl_cffi; print('curl_cffi OK')\" || echo 'curl_cffi 缺失/Termux 需编译'",
    '',
    '# 3) 确认没有残留进程抢锁',
    'ps -ef | grep -a "main.py" | grep -v grep || echo "无残留 main.py"',
    '',
    '# 4) 看最近一轮结果',
    'tail -n 40 cron.log',
    '',
    '# 5) 看历史轮次标记',
    "grep -aE '轮开始|轮结束|已自动推送' cron-history.log | tail",
  ].join('\n')));
  L.push('');

  L.push('## 7. 相关文档');
  L.push('');
  L.push('- [termux/README.md](../termux/README.md) — Android / Termux 持久化完整说明');
  L.push('- [README.md](../README.md) — 项目主页与订阅地址');
  L.push('');
  L.push('---');
  L.push('');
  L.push('*本文件由脚本生成，请勿手动编辑。*');
  L.push('');

  return L.join('\n');
}

// ========================= 主流程 =========================
function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.help) {
    console.log([
      '用法: node scripts/generate-run-commands.js [选项]',
      '',
      '选项:',
      '  -o, --out <file>   输出到指定路径（默认 RUN-COMMANDS.md）',
      '      --stdout       打印 Markdown 到标准输出，不写文件',
      '      --json         打印配置摘要 JSON，不写文件',
      '  -h, --help         显示本帮助',
    ].join('\n'));
    return;
  }

  const { cfg, notes } = loadConfig();
  const summary = buildSummary(cfg);

  if (opts.json) {
    console.log(JSON.stringify({ summary, notes }, null, 2));
    return;
  }

  const markdown = generateMarkdown(cfg, notes);

  if (opts.stdout) {
    process.stdout.write(markdown);
    return;
  }

  const outPath = path.resolve(ROOT, opts.out || 'RUN-COMMANDS.md');
  fs.writeFileSync(outPath, markdown, 'utf8');

  const rel = path.relative(ROOT, outPath) || path.basename(outPath);
  console.log(`✅ 已生成 ${rel}`);
  console.log(`   模式: ${summary.mode}`);
  console.log(`   每节点探测: ${summary.tcpProbes} 次，最低成功率: ${summary.minSuccessRate}`);
  if (notes.length) {
    console.log(`   ⚠️  ${notes.length} 条提示，详见文件顶部`);
  }
}

main();
