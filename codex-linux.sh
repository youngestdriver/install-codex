#!/usr/bin/env bash
set -euo pipefail

CODEX_DIR="$HOME/.codex"
AUTH_FILE="$CODEX_DIR/auth.json"
CONFIG_FILE="$CODEX_DIR/config.toml"
DEFAULT_BASE_URL="https://right.codes/codex/v1"

read -rsp "请输入 OpenAI API Key: " OPENAI_API_KEY
echo

if [[ -z "${OPENAI_API_KEY}" ]]; then
  echo "错误：API Key 不能为空"
  exit 1
fi

read -rp "请输入 Base URL [${DEFAULT_BASE_URL}]: " BASE_URL
BASE_URL="${BASE_URL:-$DEFAULT_BASE_URL}"

echo "安装 @openai/codex ..."
sudo npm install -g @openai/codex

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