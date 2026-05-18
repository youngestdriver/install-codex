#!/usr/bin/env bash
set -euo pipefail

SKIP_CONFIG=false
if [[ "${1:-}" == "--uninstall" ]]; then
  echo "=== 卸载 Codex / Claude Code / cc-switch-cli ==="
  echo

  read -rp "确认卸载？将删除所有相关工具和配置文件 [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 0
  fi
  echo

  # 卸载 npm 全局包
  if command -v npm >/dev/null 2>&1; then
    echo "卸载 @openai/codex ..."
    run_as_root() { command -v sudo >/dev/null 2>&1 && sudo "$@" || "$@"; }
    run_as_root npm uninstall -g @openai/codex 2>/dev/null || echo "  (跳过，可能未安装)"
    echo "卸载 @anthropic-ai/claude-code ..."
    run_as_root npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || echo "  (跳过，可能未安装)"
  else
    echo "npm 未找到，跳过 npm 包卸载。"
  fi

  # 卸载 cc-switch-cli
  echo "卸载 cc-switch-cli ..."
  rm -f "$HOME/.local/bin/cc-switch" 2>/dev/null
  rm -rf "$HOME/.local/share/cc-switch" 2>/dev/null
  rm -rf "$HOME/.local/share/cc-switch-cli" 2>/dev/null
  echo "  (如果已安装，已从 ~/.local/bin 和 ~/.local/share 中移除)"

  # 删除配置文件
  echo "删除配置文件 ..."
  rm -rf "$HOME/.codex" 2>/dev/null
  rm -f "$HOME/.claude/settings.json" 2>/dev/null
  rmdir "$HOME/.claude" 2>/dev/null || true
  echo "  已删除 ~/.codex 和 ~/.claude/settings.json"

  # 清理 shell rc 中的条目
  SHELL_RC=""
  for candidate in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
    if [[ -f "$candidate" ]]; then
      SHELL_RC="$candidate"
      break
    fi
  done
  if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
    echo "清理 $SHELL_RC 中的相关条目 ..."
    sed -i '/# cc-switch/d; /export IS_SANDBOX=1/d' "$SHELL_RC"
    echo "  已清理。"
  fi

  echo
  echo "卸载完成。"
  exit 0
fi

if [[ "${1:-}" == "--skip-config" ]]; then
  SKIP_CONFIG=true
else
  read -rp "跳过配置 API Key 和 URL？[y/N]: " SKIP_ANSWER
  if [[ "$SKIP_ANSWER" =~ ^[Yy]$ ]]; then
    SKIP_CONFIG=true
  fi
fi

CODEX_DIR="$HOME/.codex"
AUTH_FILE="$CODEX_DIR/auth.json"
CONFIG_FILE="$CODEX_DIR/config.toml"
DEFAULT_BASE_URL="https://right.codes/codex/v1"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  echo "错误：无法检测 Linux 发行版（未找到 /etc/os-release）。"
  exit 1
fi

DISTRO_ID="${ID:-}"
DISTRO_LIKE="${ID_LIKE:-}"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_shell_rc() {
  local shell_name
  shell_name="$(basename "${SHELL:-/bin/bash}")"
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    fish) echo "$HOME/.config/fish/config.fish" ;;
    *)    echo "$HOME/.bashrc" ;;  # bash, sh, 以及其他默认使用 .bashrc
  esac
}

run_as_root() {
  if command_exists sudo; then
    sudo "$@"
  else
    "$@"
  fi
}

is_debian_like() {
  [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" || " $DISTRO_LIKE " == *" debian "* ]]
}

is_arch_like() {
  [[ "$DISTRO_ID" == "arch" || " $DISTRO_LIKE " == *" arch "* ]]
}

is_rhel_like() {
  [[ "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" || " $DISTRO_LIKE " == *" rhel "* || " $DISTRO_LIKE " == *" fedora "* ]]
}

install_nodejs() {
  echo "未检测到 npm，开始安装 Node.js 22 ..."

  if is_debian_like; then
    echo "检测到 Debian/Ubuntu 系发行版。"
    run_as_root apt update
    curl -fsSL https://deb.nodesource.com/setup_22.x | run_as_root bash -
    run_as_root apt install -y nodejs
    return
  fi

  if is_arch_like; then
    echo "检测到 Arch Linux 系发行版。"
    run_as_root pacman -Sy --noconfirm nodejs npm
    return
  fi

  if is_rhel_like; then
    echo "检测到 CentOS/RHEL 系发行版。"
    if command_exists dnf; then
      run_as_root dnf install -y curl
      curl -fsSL https://rpm.nodesource.com/setup_22.x | run_as_root bash -
      run_as_root dnf install -y nodejs
    elif command_exists yum; then
      run_as_root yum install -y curl
      curl -fsSL https://rpm.nodesource.com/setup_22.x | run_as_root bash -
      run_as_root yum install -y nodejs
    else
      echo "错误：当前 CentOS/RHEL 系统中既没有 dnf，也没有 yum。"
      exit 1
    fi
    return
  fi

  echo "错误：暂不支持当前 Linux 发行版：${DISTRO_ID:-unknown}。"
  exit 1
}

install_bubblewrap() {
  echo "未检测到 bubblewrap，开始安装 ..."

  if is_debian_like; then
    run_as_root apt update
    run_as_root apt install -y bubblewrap
    return
  fi

  if is_arch_like; then
    run_as_root pacman -Sy --noconfirm bubblewrap
    return
  fi

  if is_rhel_like; then
    if command_exists dnf; then
      run_as_root dnf install -y bubblewrap
    elif command_exists yum; then
      run_as_root yum install -y bubblewrap
    else
      echo "错误：当前 CentOS/RHEL 系统中既没有 dnf，也没有 yum。"
      exit 1
    fi
    return
  fi

  echo "错误：暂不支持当前 Linux 发行版：${DISTRO_ID:-unknown}。"
  exit 1
}

SHELL_RC="$(detect_shell_rc)"

if [[ "$SKIP_CONFIG" != "true" ]]; then
  read -rsp "请输入 OpenAI API Key: " OPENAI_API_KEY
  echo

  if [[ -z "${OPENAI_API_KEY}" ]]; then
    echo "错误：API Key 不能为空。"
    exit 1
  fi

  read -rp "请输入 Base URL [${DEFAULT_BASE_URL}]: " BASE_URL
  BASE_URL="${BASE_URL:-$DEFAULT_BASE_URL}"

  read -rsp "请输入 DeepSeek API Key (用于 Claude Code): " DEEPSEEK_API_KEY
  echo

  if [[ -z "${DEEPSEEK_API_KEY}" ]]; then
    echo "错误：DeepSeek API Key 不能为空。"
    exit 1
  fi
fi

if ! command_exists npm; then
  install_nodejs
fi

if ! command_exists bwrap; then
  install_bubblewrap
fi

echo "安装 @openai/codex ..."
run_as_root npm install -g @openai/codex

echo "安装 @anthropic-ai/claude-code ..."
run_as_root npm install -g @anthropic-ai/claude-code

echo "安装 cc-switch-cli (SaladDay) ..."
if ! command_exists cc-switch; then
  export CC_SWITCH_FORCE=1
  curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash
  # 确保 cc-switch 在当前会话中可用
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"  # cc-switch' >> "$SHELL_RC"
fi

# 将 IS_SANDBOX=1 写入 Shell 配置文件
if ! grep -q 'export IS_SANDBOX=1' "$SHELL_RC" 2>/dev/null; then
  echo 'export IS_SANDBOX=1' >> "$SHELL_RC"
fi

if [[ "$SKIP_CONFIG" != "true" ]]; then
  echo "配置 Claude Code 使用 DeepSeek ..."
  CLAUDE_DIR="$HOME/.claude"
  mkdir -p "$CLAUDE_DIR"
cat > "$CLAUDE_DIR/settings.json" <<EOF
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "${DEEPSEEK_API_KEY}",
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_MODEL": "deepseek-v4-pro[1M]",
    "ANTHROPIC_DEFAULT_MODEL": "deepseek-v4-pro[1M]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1M]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
    "ANTHROPIC_MODEL_SONNET": "deepseek-v4-pro[1M]",
    "ANTHROPIC_REASONING_MODEL": "deepseek-v4-pro[1M]",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK": "1",
    "CLAUDE_CODE_EFFORT_LEVEL": "max"
  },
  "includeCoAuthoredBy": true,
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "skipDangerousModePermissionPrompt": true
}
EOF
chmod 700 "$CLAUDE_DIR"

echo "创建配置目录 ..."
mkdir -p "$CODEX_DIR"

echo "写入 $AUTH_FILE ..."
cat > "$AUTH_FILE" <<EOF
{
  "OPENAI_API_KEY": "${OPENAI_API_KEY}"
}
EOF

echo "写入 $CONFIG_FILE ..."
cat > "$CONFIG_FILE" <<EOF
model_provider = "rightcode"
model = "gpt-5.4"
model_reasoning_effort = "high"
network_access = "enabled"
disable_response_storage = true
windows_wsl_setup_acknowledged = true
model_verbosity = "high"

[model_providers.rightcode]
name = "rightcode"
base_url = "${BASE_URL}"
wire_api = "responses"
requires_openai_auth = true
EOF

chmod 700 "$CODEX_DIR"
chmod 600 "$AUTH_FILE" "$CONFIG_FILE"

echo
echo "完成。已生成："
echo "  - $AUTH_FILE"
echo "  - $CONFIG_FILE"
echo "  - $CLAUDE_DIR/settings.json"
echo
fi

echo "已安装："
echo "  - @openai/codex"
echo "  - @anthropic-ai/claude-code"
echo "  - cc-switch-cli"
echo
echo "提示：运行 cc-switch 可切换 Claude Code 的不同 provider。"
echo "      运行 claude 可启动 Claude Code。"
