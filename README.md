# install-codex

用于在 Linux 环境下初始化 Codex 配置并安装 `@openai/codex` 的脚本。

## 一键启动

### Linux: Ubuntu / Debian / Arch Linux / CentOS

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/youngestdriver/install-codex/refs/heads/main/codex-linux.sh)"
```

脚本会自动识别当前 Linux 发行版，并按系统使用对应的包管理器安装依赖：

- Ubuntu / Debian 使用 `apt`
- Arch Linux 使用 `pacman`
- CentOS / RHEL 兼容系统使用 `dnf` 或 `yum`

运行后会交互式输入：

- `OpenAI API Key`
- `Base URL`（默认：`https://right.codes/codex/v1`）
