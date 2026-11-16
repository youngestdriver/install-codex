# install-codex

用于在 Linux 环境下初始化 AI 编程 CLI Harness 及 CC-Switch CLI 的脚本。

## 一键安装

### Linux: Ubuntu / Debian / Arch Linux / CentOS

```bash
curl -sSL -o install.sh https://raw.githubusercontent.com/youngestdriver/install-codex/refs/heads/main/codex-linux.sh
bash install.sh
```

运行前会先询问**是否需要配置系统代理**（`[y/N]` 默认 `N`；选 `y` 时优先从 `https://url.qzh.su/proxy` 拉取 [proxy-init](https://github.com/youngestdriver/proxy-init) 并在失败时回退至 GitHub raw，通过临时文件执行并在完成后自动使 `/etc/profile.d/90-proxy.sh` 在当前安装流程中生效；若传入 `--harness` 且未指定 `--proxy` 则跳过询问）。

随后会先自动检测本机已安装的工具，并弹出交互式多选界面（支持 `↑/↓` 或 `j/k` 移动、`空格` 勾选/取消、`a` 全选/全不选、`Enter` 确认、`q` 退出）：未安装项以 `[*]` / `[ ]` 表示并标记 `[未安装]`，已安装项默认不重复勾选、以 `[✓]` 及 `[已安装]` 标识（按空格可切换为 `[+]` 重装/更新）；**默认预勾选尚未安装的 `claude`、`codex`、`cc-switch`**：

1. `claude` — Claude Code (`@anthropic-ai/claude-code`)
2. `codex` — OpenAI Codex (`@openai/codex`)
3. `dsh` — DeepSeek Harness (`@deepseek-ai/dsh`，需 Node ≥ 24.9.0)
4. `agy` — Google Antigravity CLI (`agy` 官方二进制)
5. `grok` — xAI Grok Build (`@xai-official/grok`)
6. `gemini` — Gemini CLI (`@google/gemini-cli`)
7. `opencode` — OpenCode (`opencode-ai`，需 Node ≥ 22.19.0)
8. `pi` — Pi Coding Agent (`@earendil-works/pi-coding-agent`，需 Node ≥ 22.19.0)
9. `cc-switch` — CC-Switch CLI（provider 切换与 WebDAV 同步工具）

依赖安装策略：

- **Node.js** — 仅当选择了任一 npm 工具时按最高版本需求检查：
  - 选 `dsh` 需 Node ≥ 24.9.0；选 `opencode` / `pi` 需 Node ≥ 22.19.0；其余 npm 工具需 Node ≥ 22.0.0
  - 满足则复用现有环境，否则通过 [nvm](https://github.com/nvm-sh/nvm) 安装 Node 24 LTS（用户级，无需 root）
  - 仅安装 `agy` / `cc-switch` 时不会安装 Node.js
- **bubblewrap** — 仅当选择 `claude` 或 `codex` 时按发行版安装（Ubuntu/Debian 用 `apt`，Arch Linux 用 `pacman`，CentOS/RHEL 兼容系统用 `dnf` 或 `yum`）
- **Antigravity CLI (`agy`) 权限初始化** — 勾选 `agy` 时会自动将 `~/.gemini/antigravity-cli/settings.json` 初始化为最高权限（`agentMode: "auto"`、`toolPermission: "always-proceed"`、`artifactReviewPolicy: "always-proceed"`、`allowNonWorkspaceAccess: true`、`enableTerminalSandbox: false`，并在 `permissions.allow` 中放行 `read_file(*)`、`write_file(*)`、`command(*)`、`mcp(*)`、`read_url(*)`、`execute_url(*)`、`download_url(*)` 全部 7 类动作；若已有配置文件则合并保留原字段与自定义 `ask`/`deny` 规则）
- **cc-switch-cli 与 WebDAV** — 勾选 `cc-switch` 时安装并写入 `PATH` / `IS_SANDBOX=1`，随后询问是否从 WebDAV 导入配置（`[y/N]` 默认 `N`）；导入后会自动为本次已选且支持的单配置工具（`claude`、`codex`、`gemini`、`opencode`）应用当前 provider

> **CC-Switch 支持说明**：脚本安装的 `cc-switch-cli`（[SaladDay/cc-switch-cli](https://github.com/SaladDay/cc-switch-cli)）支持管理 `claude`、`codex`、`gemini`、`opencode`、`pi` 等，**暂不支持**管理 `dsh`、`agy`、`grok`（这三款需按各自方式登录或配置 API Key；若使用桌面端 [CC-Switch](https://github.com/farion1231/cc-switch)，桌面端已支持 `grok`、`dsh`、`agy` 等）。

### macOS（手动安装）

`codex-linux.sh` 仅支持 Linux（依赖 `/etc/os-release`、apt/pacman/dnf、bubblewrap），macOS 上按以下步骤手动安装：

```bash
# 1. Node
brew install node

# 2. Codex / Claude Code（官方安装器）
curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh

# 3. cc-switch-cli（官方 install.sh 已支持 Darwin）
curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash
```

**环境变量必须写入 `~/.zshenv`**（macOS 上只写 `~/.zshrc` 不生效；`~/.zshenv` 对所有 zsh 进程生效，含非交互调用）：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"  # cc-switch' >> ~/.zshenv
echo 'export IS_SANDBOX=1  # cc-switch' >> ~/.zshenv
source ~/.zshenv
printenv IS_SANDBOX   # 验证输出 1
```

`# cc-switch` 标记与 Linux 脚本保持一致，便于统一清理。

## 选项

```bash
bash install.sh --proxy 127.0.0.1:7890                # 安装前非交互配置系统代理（支持 http/socks5）
bash install.sh --harness claude,codex,dsh,cc-switch  # 非交互指定要安装的工具（支持 all）
bash install.sh --skip-config                         # 跳过 WebDAV 配置询问，仅安装工具
bash install.sh --uninstall                           # 交互多选卸载已安装工具（也可配合 --harness）
bash install.sh --help                                # 查看帮助信息
```

## 使用

```bash
cc-switch   # 切换 Claude / Codex / Gemini / OpenCode / Pi 的 provider
claude      # 启动 Claude Code
codex       # 启动 Codex
dsh web     # 启动 DeepSeek Harness Web UI（或直接运行 dsh）
agy         # 启动 Antigravity CLI
grok        # 启动 Grok Build
gemini      # 启动 Gemini CLI
opencode    # 启动 OpenCode
pi          # 启动 Pi Coding Agent
```

## 卸载

```bash
bash install.sh --uninstall
```

卸载时会先自动检测本机已安装的工具并弹出 `[*]` 方向键多选列表（已安装项默认预勾选），确认后仅移除所选工具及其对应配置；若不再保留 `cc-switch` / `agy` 或 npm 工具，也会按需清理 shell rc 中的 `# cc-switch`、`# local-bin`、`# nvm` 条目（`~/.nvm`、`~/.gemini/antigravity-cli` 及系统级 `proxy-init` 配置保留，不会被删除；如需撤销代理可单独运行 `proxy-init.sh --uninstall`）。
