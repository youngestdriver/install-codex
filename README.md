# install-codex

用于在 Linux 环境下初始化 Codex 配置并安装 `@openai/codex` 的脚本。

## 一键启动

### Linux: Ubuntu / Debian

```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/youngestdriver/install-codex/refs/heads/main/codex-linux.sh)"
```

运行后会交互式输入：

- `OpenAI API Key`
- `Base URL`（默认：`https://right.codes/codex/v1`）

如果系统中没有 `npm`，脚本会自动执行：

- `sudo apt update`
- 安装 Node.js 22（NodeSource）
- `sudo apt install -y nodejs`
- `sudo apt install -y bubblewrap`
