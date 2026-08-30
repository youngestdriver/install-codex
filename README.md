# install-codex

用于在 Linux 环境下初始化 Codex / Claude Code / CC-switch 的脚本。

## 一键安装

### Linux: Ubuntu / Debian / Arch Linux / CentOS

```bash
curl -sSL -o install.sh https://raw.githubusercontent.com/youngestdriver/install-codex/refs/heads/main/codex-linux.sh
bash install.sh
```

依赖安装策略：

- **Node.js** — 已有 npm 且 Node ≥ 22 时直接用现有环境；否则通过 [nvm](https://github.com/nvm-sh/nvm) 安装 Node 24 LTS（用户级，无需 root）
- **bubblewrap** — 按发行版使用对应包管理器（Ubuntu/Debian 用 `apt`，Arch Linux 用 `pacman`，CentOS/RHEL 兼容系统用 `dnf` 或 `yum`）

运行后交互式询问配置方式（`[y/N]` 默认均为 `N`，直接回车即选 `N`）：

1. `跳过配置 API Key 和 URL？` — 选择跳过则直接安装
2. 否则询问 `从 WebDAV 导入 cc-switch 配置？`：
   - 选择导入 → 读取 WebDAV 凭据，从云端拉取 cc-switch 配置并应用到应用目录
   - 选择不导入 → 等同跳过配置，直接安装（配置由 cc-switch 自行管理）

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
bash install.sh --skip-config   # 跳过所有配置询问，仅安装工具
bash install.sh --uninstall     # 卸载所有工具和配置文件
```

## 安装内容

- **Codex** — `@openai/codex` 全局 npm 安装（凭据配置通过 cc-switch / WebDAV 导入）
- **Claude Code** — `@anthropic-ai/claude-code` 全局 npm 安装
- **cc-switch-cli** — 用于管理 Claude Code / Codex 等工具的 provider 切换

## 使用

```bash
cc-switch   # 切换 provider
claude      # 启动 Claude Code
codex       # 启动 Codex
```

## 卸载

```bash
bash install.sh --uninstall
```

将删除：npm 全局包（codex、claude-code）、cc-switch-cli、`~/.codex`、`~/.claude/settings.json`，以及 shell rc 中的相关条目（`# cc-switch`、`# nvm`）。`~/.nvm` 本身保留，不会被删除。
