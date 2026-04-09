#!/usr/bin/env bash
set -euo pipefail

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

read -rsp "请输入 OpenAI API Key: " OPENAI_API_KEY
echo

if [[ -z "${OPENAI_API_KEY}" ]]; then
  echo "错误：API Key 不能为空。"
  exit 1
fi

read -rp "请输入 Base URL [${DEFAULT_BASE_URL}]: " BASE_URL
BASE_URL="${BASE_URL:-$DEFAULT_BASE_URL}"

if ! command_exists npm; then
  install_nodejs
fi

if ! command_exists bwrap; then
  install_bubblewrap
fi

echo "安装 @openai/codex ..."
run_as_root npm install -g @openai/codex

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
