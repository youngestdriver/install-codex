# install-codex

用于在 Linux 环境下初始化 Codex / Claude Code / CC-switch 的脚本。

## 一键安装

### Linux: Ubuntu / Debian / Arch Linux / CentOS

```bash
curl -sSL -o install.sh https://raw.githubusercontent.com/youngestdriver/install-codex/refs/heads/main/codex-linux.sh
bash install.sh
```

脚本会自动识别当前 Linux 发行版，并按系统使用对应的包管理器安装依赖：

- Ubuntu / Debian 使用 `apt`
- Arch Linux 使用 `pacman`
- CentOS / RHEL 兼容系统使用 `dnf` 或 `yum`

运行后首先询问是否跳过配置，选择否后会交互式输入：

- `OpenAI API Key` — 用于 Codex
- `Base URL`（默认：`https://right.codes/codex/v1`）— 用于 Codex
- `DeepSeek API Key` — 用于 Claude Code（通过 DeepSeek 的 Anthropic 兼容 API）

## 选项

```bash
bash install.sh --skip-config   # 跳过 API Key 和 URL 设置，仅安装工具
bash install.sh --uninstall     # 卸载所有工具和配置文件
```

## 安装内容

- **Codex** — `@openai/codex` 全局 npm 安装，并生成 `~/.codex/auth.json` 和 `~/.codex/config.toml`
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

将删除：npm 全局包（codex、claude-code）、cc-switch-cli、`~/.codex`、`~/.claude/settings.json`，以及 shell rc 中的相关条目。
