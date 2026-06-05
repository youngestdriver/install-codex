#!/usr/bin/env bash
set -euo pipefail

SKIP_CONFIG=false
WEBDAV_IMPORT=false

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_as_root() {
  if command_exists sudo; then
    sudo "$@"
  else
    "$@"
  fi
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

is_fish_rc() {
  [[ "$1" == *"/fish/config.fish" ]]
}

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
  if command_exists npm; then
    NPM_GLOBAL="$(run_as_root npm root -g)"

    for pkg in "@openai/codex" "@anthropic-ai/claude-code"; do
      echo "卸载 ${pkg} ..."
      if ! run_as_root npm uninstall -g "$pkg" 2>/dev/null; then
        echo "  npm 卸载失败，直接删除文件 ..."
        pkg_dir="${NPM_GLOBAL}/${pkg}"
        if [[ -d "$pkg_dir" ]]; then
          run_as_root rm -rf "$pkg_dir"
          echo "  已删除 ${pkg_dir}"
        else
          echo "  (跳过，未找到 ${pkg_dir})"
        fi
      fi
    done

    # 清理可能残留的 bin 软链接
    for bin_link in /usr/bin/codex /usr/bin/claude /usr/local/bin/codex /usr/local/bin/claude; do
      if [[ -L "$bin_link" ]]; then
        run_as_root rm -f "$bin_link"
        echo "  已删除残留链接 ${bin_link}"
      fi
    done
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
  rm -rf "$HOME/.cc-switch" 2>/dev/null
  echo "  已删除 ~/.codex、~/.claude/settings.json 和 ~/.cc-switch"

  # 清理 shell rc 中的条目（与安装时写入的文件保持一致）
  SHELL_RC="$(detect_shell_rc)"
  if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
    echo "清理 $SHELL_RC 中的相关条目 ..."
    sed -i '/# cc-switch/d' "$SHELL_RC"
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
  else
    read -rp "从 WebDAV 导入配置？[y/N]: " WEBDAV_ANSWER
    if [[ "$WEBDAV_ANSWER" =~ ^[Yy]$ ]]; then
      WEBDAV_IMPORT=true
      read -rp "WebDAV Base URL: " WEBDAV_URL
      read -rp "WebDAV Username: " WEBDAV_USER
      read -rsp "WebDAV Password: " WEBDAV_PASS
      echo
    fi
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

if [[ "$SKIP_CONFIG" != "true" && "$WEBDAV_IMPORT" != "true" ]]; then
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

install_npm_pkg() {
  local pkg="$1" rc
  echo "安装 ${pkg} ..."
  run_as_root npm install -g "$pkg" && return 0
  rc=$?
  local pkg_dir="$(run_as_root npm root -g)/${pkg}"
  if [[ -d "$pkg_dir" ]]; then
    echo "  npm install 失败 (exit ${rc})，可能是残留目录导致，清理后重试 ..."
    run_as_root rm -rf "$pkg_dir"
    run_as_root npm install -g "$pkg"
  else
    return $rc
  fi
}

install_npm_pkg @openai/codex
install_npm_pkg @anthropic-ai/claude-code

echo "安装 cc-switch-cli (SaladDay) ..."
if ! command_exists cc-switch; then
  export CC_SWITCH_FORCE=1
  curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash
  # 确保 cc-switch 在当前会话中可用
  export PATH="$HOME/.local/bin:$PATH"
  if is_fish_rc "$SHELL_RC"; then
    echo 'set -gx PATH "$HOME/.local/bin" $PATH  # cc-switch' >> "$SHELL_RC"
  else
    echo 'export PATH="$HOME/.local/bin:$PATH"  # cc-switch' >> "$SHELL_RC"
  fi
fi

# 将 IS_SANDBOX=1 尽早写入，避免后续任何步骤失败导致遗漏
if ! grep -q '# cc-switch' "$SHELL_RC" 2>/dev/null || ! grep -q 'IS_SANDBOX' "$SHELL_RC" 2>/dev/null; then
  if is_fish_rc "$SHELL_RC"; then
    echo 'set -gx IS_SANDBOX 1  # cc-switch' >> "$SHELL_RC"
  else
    echo 'export IS_SANDBOX=1  # cc-switch' >> "$SHELL_RC"
  fi
fi
export IS_SANDBOX=1  # 当前会话也立即生效

if [[ "$WEBDAV_IMPORT" == "true" ]]; then
  echo "从 WebDAV 导入配置 ..."
  if ! "$HOME/.local/bin/cc-switch" config webdav set \
    --base-url "$WEBDAV_URL" \
    --username "$WEBDAV_USER" \
    --password "$WEBDAV_PASS" \
    --enable; then
    echo "错误: WebDAV 配置设置失败，跳过导入。"
  elif "$HOME/.local/bin/cc-switch" config webdav download; then
    echo "WebDAV 配置下载完成，正在应用配置到应用目录 ..."
    # download 只恢复到 cc-switch 内部数据库，需通过 provider switch 将配置写入应用目录
    CC_SETTINGS="$HOME/.cc-switch/settings.json"
    if [[ -f "$CC_SETTINGS" ]]; then
      CLAUDE_PROVIDER=$(grep '"currentProviderClaude"' "$CC_SETTINGS" 2>/dev/null | grep -o '[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}' | head -1 || true)
      if [[ -n "$CLAUDE_PROVIDER" ]]; then
        "$HOME/.local/bin/cc-switch" provider switch "$CLAUDE_PROVIDER" --app claude 2>/dev/null || true
      fi
      CODEX_PROVIDER=$(grep '"currentProviderCodex"' "$CC_SETTINGS" 2>/dev/null | grep -o '[a-f0-9]\{8\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{4\}-[a-f0-9]\{12\}' | head -1 || true)
      if [[ -n "$CODEX_PROVIDER" ]]; then
        "$HOME/.local/bin/cc-switch" provider switch "$CODEX_PROVIDER" --app codex 2>/dev/null || true
      fi
    fi
    echo "WebDAV 配置导入完成。"
  else
    echo "警告: WebDAV 配置拉取失败，请检查网络连接和凭据后重试。"
  fi
fi

if [[ "$SKIP_CONFIG" != "true" && "$WEBDAV_IMPORT" != "true" ]]; then
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
chmod 600 "$CLAUDE_DIR/settings.json"

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
echo "提示：运行 source $SHELL_RC 或重新打开终端以使 PATH 生效。"
echo "      运行 cc-switch 可切换 Claude Code 的不同 provider。"
echo "      运行 claude 可启动 Claude Code。"
