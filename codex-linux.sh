#!/usr/bin/env bash
set -euo pipefail

# 确保 HOME 始终有值（某些 LXC 容器环境中 HOME 可能未设置）
if [[ -z "${HOME:-}" ]]; then
  HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"
  if [[ -z "$HOME" ]]; then
    echo "错误：无法确定 HOME 目录。" >&2
    exit 1
  fi
  export HOME
fi

ACTION="install"
SKIP_CONFIG=false
WEBDAV_IMPORT=false
HARNESS_ARG=""
PROXY_ARG=""
PROXY_INIT_URL="${PROXY_INIT_URL:-https://url.qzh.su/proxy}"
PROXY_INIT_FALLBACK_URL="${PROXY_INIT_FALLBACK_URL:-https://raw.githubusercontent.com/youngestdriver/proxy-init/main/proxy-init.sh}"
PROXY_ENV_FILE="${PROXY_ENV_FILE:-/etc/profile.d/90-proxy.sh}"

NVM_NODE=false
NVM_DIR="$HOME/.nvm"
NVM_VERSION="v0.40.7"

# 受管工具注册表（保持固定顺序；新增工具只需在此表与对应处理器登记）
TOOL_IDS=(
  "claude"
  "codex"
  "dsh"
  "agy"
  "grok"
  "gemini"
  "opencode"
  "pi"
  "cc-switch"
)
TOOL_LABELS=(
  "Claude Code       (@anthropic-ai/claude-code · cc-switch 支持)"
  "OpenAI Codex      (@openai/codex · cc-switch 支持)"
  "DeepSeek Harness  (@deepseek-ai/dsh · 需 Node >= 24.9.0)"
  "Antigravity CLI   (agy 官方二进制)"
  "Grok Build        (@xai-official/grok)"
  "Gemini CLI        (@google/gemini-cli · cc-switch 支持)"
  "OpenCode          (opencode-ai · cc-switch 支持)"
  "Pi Coding Agent   (@earendil-works/pi-coding-agent · cc-switch 支持)"
  "CC-Switch CLI     (provider 切换与 WebDAV 同步工具)"
)
# npm 包名；非 npm 工具留空
TOOL_PKGS=(
  "@anthropic-ai/claude-code"
  "@openai/codex"
  "@deepseek-ai/dsh"
  ""
  "@xai-official/grok"
  "@google/gemini-cli"
  "opencode-ai"
  "@earendil-works/pi-coding-agent"
  ""
)
# 主命令名（用于卸载清理软链与检测）
TOOL_BINS=(
  "claude"
  "codex"
  "dsh"
  "agy"
  "grok"
  "gemini"
  "opencode"
  "pi"
  "cc-switch"
)
# 最低 Node 主/次版本号（非 npm 工具为 0 0）
TOOL_MIN_NODE_MAJOR=(22 22 24 0 22 22 22 22 0)
TOOL_MIN_NODE_MINOR=(0  0  9  0 0  0  19 19 0)

# 默认安装勾选：claude、codex、cc-switch
TOOL_SELECTED=(1 1 0 0 0 0 0 0 1)
TOOL_INSTALLED=(0 0 0 0 0 0 0 0 0)

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

tool_index() {
  local target="$1" i
  for i in "${!TOOL_IDS[@]}"; do
    if [[ "${TOOL_IDS[$i]}" == "$target" ]]; then
      echo "$i"
      return 0
    fi
  done
  return 1
}

is_selected() {
  local idx
  idx="$(tool_index "$1")" || return 1
  [[ "${TOOL_SELECTED[$idx]}" == "1" ]]
}

set_selected() {
  local idx
  idx="$(tool_index "$1")" || return 1
  TOOL_SELECTED[$idx]="$2"
}

reset_selection() {
  local i
  for i in "${!TOOL_IDS[@]}"; do
    TOOL_SELECTED[$i]=0
  done
}

select_all_tools() {
  local i
  for i in "${!TOOL_IDS[@]}"; do
    TOOL_SELECTED[$i]=1
  done
}

selected_count() {
  local count=0 i
  for i in "${!TOOL_IDS[@]}"; do
    if [[ "${TOOL_SELECTED[$i]}" == "1" ]]; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

show_usage() {
  cat <<'EOF'
用法: bash install.sh [选项]

选项:
  --harness <列表>    指定要安装/卸载的工具（逗号或空格分隔，或使用 all 全选）
                      可选: claude, codex, dsh, agy, grok, gemini, opencode, pi, cc-switch
                      示例: --harness claude,codex,dsh,cc-switch
                            --harness all
  --proxy <地址>      安装前调用 proxy-init 配置系统代理（如 127.0.0.1:7890）
  --skip-config       跳过 WebDAV 配置询问，仅安装工具
  --uninstall         进入卸载模式（可交互多选或配合 --harness 指定）
  -h, --help          显示此帮助信息
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --uninstall)
        ACTION="uninstall"
        ;;
      --skip-config)
        SKIP_CONFIG=true
        ;;
      --proxy)
        if [[ -z "${2:-}" ]]; then
          echo "错误: $1 需要指定代理地址。" >&2
          show_usage >&2
          exit 1
        fi
        PROXY_ARG="$2"
        shift
        ;;
      --proxy=*)
        local pval="${1#*=}"
        if [[ -z "$pval" ]]; then
          echo "错误: ${1%%=*} 需要指定代理地址。" >&2
          show_usage >&2
          exit 1
        fi
        PROXY_ARG="$pval"
        ;;
      --harness|--harnesses)
        if [[ -z "${2:-}" ]]; then
          echo "错误: $1 需要指定工具列表。" >&2
          show_usage >&2
          exit 1
        fi
        HARNESS_ARG="${HARNESS_ARG:+${HARNESS_ARG},}$2"
        shift
        ;;
      --harness=*|--harnesses=*)
        local val="${1#*=}"
        if [[ -z "$val" ]]; then
          echo "错误: ${1%%=*} 需要指定工具列表。" >&2
          show_usage >&2
          exit 1
        fi
        HARNESS_ARG="${HARNESS_ARG:+${HARNESS_ARG},}$val"
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        echo "错误: 未知参数 '$1'。" >&2
        show_usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

enable_tool_token() {
  local token="${1,,}"
  case "$token" in
    1|claude|claude-code)             set_selected "claude" 1 ;;
    2|codex)                          set_selected "codex" 1 ;;
    3|dsh|deepseek|deepseek-harness)  set_selected "dsh" 1 ;;
    4|agy|antigravity)                set_selected "agy" 1 ;;
    5|grok|grok-build|grok_build)     set_selected "grok" 1 ;;
    6|gemini|gemini-cli)              set_selected "gemini" 1 ;;
    7|opencode|opencode-ai)           set_selected "opencode" 1 ;;
    8|pi|pi-coding-agent)             set_selected "pi" 1 ;;
    9|cc-switch|cc-switch-cli|cc)     set_selected "cc-switch" 1 ;;
    all|a)                            select_all_tools ;;
    *)                                return 1 ;;
  esac
}

apply_tool_list() {
  local raw="$1" token
  local normalized="${raw//,/ }"
  reset_selection

  for token in $normalized; do
    if ! enable_tool_token "$token"; then
      echo "错误: 不支持的工具选项 '$token'。" >&2
      return 1
    fi
  done

  if (( $(selected_count) == 0 )); then
    echo "错误: 请至少选择一项。" >&2
    return 1
  fi
}

needs_node() {
  local i
  for i in "${!TOOL_IDS[@]}"; do
    if [[ "${TOOL_SELECTED[$i]}" == "1" && -n "${TOOL_PKGS[$i]}" ]]; then
      return 0
    fi
  done
  return 1
}

# 计算所选 npm 工具中的最高 Node 版本门槛（major minor 输出到 stdout）
required_node_version() {
  local max_major=22 max_minor=0 i maj min
  for i in "${!TOOL_IDS[@]}"; do
    if [[ "${TOOL_SELECTED[$i]}" == "1" && -n "${TOOL_PKGS[$i]}" ]]; then
      maj="${TOOL_MIN_NODE_MAJOR[$i]}"
      min="${TOOL_MIN_NODE_MINOR[$i]}"
      if (( maj > max_major || (maj == max_major && min > max_minor) )); then
        max_major="$maj"
        max_minor="$min"
      fi
    fi
  done
  echo "$max_major $max_minor"
}

needs_bwrap() {
  is_selected "claude" || is_selected "codex"
}

needs_local_bin_path() {
  is_selected "agy" || is_selected "cc-switch"
}

# 是否任一工具还需保留 nvm（卸载后判断是否可清理 # nvm）
any_npm_tool_installed() {
  local i pkg
  for i in "${!TOOL_IDS[@]}"; do
    pkg="${TOOL_PKGS[$i]}"
    [[ -n "$pkg" ]] || continue
    if is_pkg_installed "$pkg" "${TOOL_BINS[$i]}"; then
      return 0
    fi
  done
  return 1
}

# 检测 npm 可用且 Node 版本 >= min_major.min_minor；满足则直接用现有环境，不装 nvm
node_version_ok() {
  local min_major="${1:-22}" min_minor="${2:-0}"
  command_exists npm || return 1
  command_exists node || return 1
  local ver major minor
  ver="$(node -p 'process.versions.node' 2>/dev/null)" || return 1
  major="${ver%%.*}"
  minor="${ver#*.}"
  minor="${minor%%.*}"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  (( major > min_major || (major == min_major && minor >= min_minor) ))
}

# 加载已存在的 nvm（供卸载检测或非交互环境复用）
try_load_nvm() {
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    export NVM_DIR
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    if nvm which default >/dev/null 2>&1; then
      nvm use default >/dev/null 2>&1 || true
      return 0
    fi
  fi
  return 1
}

# 通过 nvm 安装 Node 24 LTS（无 npm 或 Node 版本不满足要求时的路径）
install_nvm_node() {
  echo "未检测到满足版本要求的 Node.js，通过 nvm 安装 Node 24 LTS ..."

  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo "安装 nvm ${NVM_VERSION} ..."
    ensure_curl
    mkdir -p "$NVM_DIR"
    if ! curl -fsSL "https://github.com/nvm-sh/nvm/archive/refs/tags/${NVM_VERSION}.tar.gz" | \
      tar -xz --strip-components=1 -C "$NVM_DIR"; then
      echo "错误: nvm 安装失败，无法继续。" >&2
      exit 1
    fi
  else
    echo "检测到已有 nvm，跳过安装。"
  fi

  export NVM_DIR
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"

  nvm install 24
  nvm alias default 24 >/dev/null
  echo "已激活 Node $(node -v)。"

  if [[ -n "$SHELL_RC" ]] && ! grep -q '# nvm' "$SHELL_RC" 2>/dev/null; then
    mkdir -p "$(dirname "$SHELL_RC")"
    if is_fish_rc "$SHELL_RC"; then
      cat >> "$SHELL_RC" <<'NVM_EOF'
set -gx NVM_DIR "$HOME/.nvm"  # nvm
if test -s "$NVM_DIR/nvm.fish"  # nvm
  source "$NVM_DIR/nvm.fish"  # nvm
end  # nvm
NVM_EOF
    else
      cat >> "$SHELL_RC" <<'NVM_EOF'
export NVM_DIR="$HOME/.nvm"  # nvm
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # nvm
NVM_EOF
    fi
    echo "已将 nvm 加载段写入 $SHELL_RC。"
  fi
}

# npm 执行封装：nvm 或用户级 npm 直接运行，系统级 npm 用 sudo
npm_run() {
  if [[ "$NVM_NODE" == "true" ]] \
    || { command_exists npm && [[ "$(npm prefix -g 2>/dev/null)" == "$HOME"/* ]]; }; then
    npm "$@"
  else
    run_as_root npm "$@"
  fi
}

detect_shell_rc() {
  local shell_name login_shell
  login_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
  shell_name="$(basename "${SHELL:-$login_shell}")"
  case "$shell_name" in
    zsh)  echo "$HOME/.zshrc" ;;
    fish) echo "$HOME/.config/fish/config.fish" ;;
    sh|dash|ash|ksh|mksh) echo "$HOME/.profile" ;;
    *)    echo "$HOME/.bashrc" ;;
  esac
}

is_fish_rc() {
  [[ "$1" == *"/fish/config.fish" ]]
}

# 向指定 rc 文件幂等写入环境变量块：
#   mode=cc-switch  写入 PATH + IS_SANDBOX=1（标记 '# cc-switch'）
#   mode=local-bin  仅写入 ~/.local/bin PATH（标记 '# local-bin'）
# shellcheck disable=SC2016
write_env_block() {
  local rc="$1" mode="${2:-cc-switch}"
  local marker="# ${mode}"
  if grep -q "$marker" "$rc" 2>/dev/null; then
    return 0
  fi
  mkdir -p "$(dirname "$rc")"
  if is_fish_rc "$rc"; then
    {
      echo "set -gx PATH \"\$HOME/.local/bin\" \$PATH  ${marker}"
      if [[ "$mode" == "cc-switch" ]]; then
        echo "set -gx IS_SANDBOX 1  ${marker}"
      fi
    } >> "$rc"
  else
    {
      echo "export PATH=\"\$HOME/.local/bin:\$PATH\"  ${marker}"
      if [[ "$mode" == "cc-switch" ]]; then
        echo "export IS_SANDBOX=1  ${marker}"
      fi
    } >> "$rc"
  fi
}

# 确保 login shell 也能加载 ~/.local/bin（以及 cc-switch 时的 IS_SANDBOX=1）
write_profile_guard() {
  local mode="${1:-cc-switch}"
  [[ "$SHELL_RC" == "$HOME/.bashrc" ]] || return 0

  local bash_profile="$HOME/.bash_profile"
  local profile="$HOME/.profile"

  if [[ -f "$bash_profile" ]]; then
    write_env_block "$bash_profile" "$mode"
    return 0
  fi

  if [[ -f "$profile" ]]; then
    write_env_block "$profile" "$mode"
    return 0
  fi

  cat > "$bash_profile" <<'PROFILE_EOF'
# ~/.bash_profile — created by install-codex

if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi
PROFILE_EOF
  write_env_block "$bash_profile" "$mode"
}

configure_shell_env() {
  local mode="$1"
  export PATH="$HOME/.local/bin:$PATH"
  write_env_block "$SHELL_RC" "$mode"
  if [[ "$SHELL_RC" == "$HOME/.zshrc" ]]; then
    write_env_block "$HOME/.zshenv" "$mode"
  fi
  if [[ "$mode" == "cc-switch" ]]; then
    export IS_SANDBOX=1
  fi
  write_profile_guard "$mode"
}

### 交互式 [*] 方向键多选 TUI ###

has_tty() {
  ( : <>/dev/tty ) 2>/dev/null
}

# 处理单次按键事件（供 TUI 主循环和单元测试调用）
# 返回码: 0=重绘继续, 1=确认退出循环, 2=取消退出
tui_handle_key() {
  local key="$1"
  local total="${#TOOL_IDS[@]}"
  case "$key" in
    UP|k|K)
      TUI_CURSOR=$(( (TUI_CURSOR - 1 + total) % total ))
      TUI_MSG=""
      return 0
      ;;
    DOWN|j|J)
      TUI_CURSOR=$(( (TUI_CURSOR + 1) % total ))
      TUI_MSG=""
      return 0
      ;;
    " ")
      if [[ "${TOOL_SELECTED[$TUI_CURSOR]}" == "1" ]]; then
        TOOL_SELECTED[$TUI_CURSOR]=0
      else
        TOOL_SELECTED[$TUI_CURSOR]=1
      fi
      TUI_MSG=""
      return 0
      ;;
    a|A)
      if (( $(selected_count) == total )); then
        reset_selection
      else
        select_all_tools
      fi
      TUI_MSG=""
      return 0
      ;;
    ENTER)
      if (( $(selected_count) == 0 )); then
        if [[ "$TUI_ALLOW_EMPTY" == "true" ]]; then
          return 1
        fi
        TUI_MSG="请至少选择一项（按空格勾选；已安装项 [✓] 按空格可切换为 [+] 重装）"
        return 0
      fi
      return 1
      ;;
    q|Q)
      return 2
      ;;
  esac
  return 0
}

tui_render_frame() {
  local fd="$1" title="$2" show_status="$3"
  local total="${#TOOL_IDS[@]}" i mark pointer status_tag line
  printf '\033[1m%s\033[0m\033[K\n' "$title" >&"$fd"
  if [[ "$show_status" == "true" && "$ACTION" != "uninstall" ]]; then
    printf '\033[2m操作: ↑/↓ 移动  空格 勾选/取消  a 全选/全不选  Enter 确认  q 退出（[✓] 已安装  [*] 安装  [+] 重装）\033[0m\033[K\n' >&"$fd"
  else
    printf '\033[2m操作: ↑/↓ 移动  空格 勾选/取消  a 全选/全不选  Enter 确认  q 退出\033[0m\033[K\n' >&"$fd"
  fi
  for i in "${!TOOL_IDS[@]}"; do
    if [[ "$show_status" == "true" && "$ACTION" != "uninstall" && "${TOOL_INSTALLED[$i]}" == "1" ]]; then
      if [[ "${TOOL_SELECTED[$i]}" == "1" ]]; then
        mark="[+]"
      else
        mark="[✓]"
      fi
    elif [[ "${TOOL_SELECTED[$i]}" == "1" ]]; then
      mark="[*]"
    else
      mark="[ ]"
    fi
    if (( i == TUI_CURSOR )); then
      pointer=">"
    else
      pointer=" "
    fi
    status_tag=""
    if [[ "$show_status" == "true" ]]; then
      if [[ "${TOOL_INSTALLED[$i]}" == "1" ]]; then
        status_tag=" [已安装]"
      else
        status_tag=" [未安装]"
      fi
    fi
    line=$(printf ' %s %s %-10s %s%s' "$pointer" "$mark" "${TOOL_IDS[$i]}" "${TOOL_LABELS[$i]}" "$status_tag")
    if (( i == TUI_CURSOR )); then
      printf '\033[36m%s\033[0m\033[K\n' "$line" >&"$fd"
    else
      printf '%s\033[K\n' "$line" >&"$fd"
    fi
  done
  if [[ -n "$TUI_MSG" ]]; then
    printf '\033[33m%s\033[0m\033[K\n' "$TUI_MSG" >&"$fd"
  else
    printf '已选 %d/%d 项\033[K\n' "$(selected_count)" "$total" >&"$fd"
  fi
}

# 在 /dev/tty 上运行交互多选菜单；show_status=true 时显示已安装状态
tui_multiselect() {
  local title="$1" show_status="${2:-false}" allow_empty="${3:-false}"
  TUI_CURSOR=0
  TUI_MSG=""
  TUI_ALLOW_EMPTY="$allow_empty"

  exec 3<>/dev/tty
  printf '\033[?25l' >&3
  # 退出或中断时恢复终端光标并关闭 fd 3
  trap 'printf "\033[?25h" >&3 2>/dev/null || true; exec 3>&- 2>/dev/null || true' RETURN INT TERM

  local frame_lines=$(( ${#TOOL_IDS[@]} + 3 ))
  local key seq action rc=0
  tui_render_frame 3 "$title" "$show_status"

  while true; do
    action=""
    if ! IFS= read -rsn1 key <&3; then
      rc=2
      break
    fi

    if [[ "$key" == $'\x1b' ]]; then
      seq=""
      IFS= read -rsn2 -t 0.05 seq <&3 || true
      case "$seq" in
        "[A"|"OA") action="UP" ;;
        "[B"|"OB") action="DOWN" ;;
        *)         continue ;;
      esac
    elif [[ -z "$key" || "$key" == $'\n' || "$key" == $'\r' ]]; then
      action="ENTER"
    else
      action="$key"
    fi

    if tui_handle_key "$action"; then
      printf '\033[%dA' "$frame_lines" >&3
      tui_render_frame 3 "$title" "$show_status"
    else
      rc=$?
      break
    fi
  done

  printf '\033[?25h' >&3
  exec 3>&-
  trap - RETURN INT TERM

  if (( rc == 2 )); then
    echo "已取消。"
    exit 0
  fi
  echo
}

### 交互询问 ###

select_tools_for_install() {
  if [[ -n "$HARNESS_ARG" ]]; then
    if ! apply_tool_list "$HARNESS_ARG"; then
      exit 1
    fi
    return
  fi

  if has_tty; then
    detect_installed_tools
    local i
    for i in "${!TOOL_IDS[@]}"; do
      if [[ "${TOOL_INSTALLED[$i]}" == "1" ]]; then
        TOOL_SELECTED[$i]=0
      fi
    done
    tui_multiselect "请选择要安装的 CLI 工具：" "true" "false"
  else
    echo "未检测到交互终端且未指定 --harness，使用默认选择：claude, codex, cc-switch。"
  fi
}

# 选择跳过配置则返回 0（[y/N] 默认 N）
ask_skip_config() {
  local ans
  read -rp "跳过配置 API Key 和 URL？[y/N]: " ans </dev/tty
  [[ "$ans" =~ ^[Yy]$ ]]
}

# 选择 WebDAV 导入则返回 0，并读取凭据（[y/N] 默认 N）
ask_webdav() {
  local ans
  read -rp "从 WebDAV 导入 cc-switch 配置？[y/N]: " ans </dev/tty
  [[ "$ans" =~ ^[Yy]$ ]] || return 1
  read -rp "WebDAV Base URL: " WEBDAV_URL </dev/tty
  read -rp "WebDAV Username: " WEBDAV_USER </dev/tty
  read -rsp "WebDAV Password: " WEBDAV_PASS </dev/tty
  echo
}

confirm_uninstall() {
  local confirm
  if ! has_tty; then
    return 0
  fi
  read -rp "确认卸载已勾选的工具及相关配置？[y/N]: " confirm </dev/tty
  [[ "$confirm" =~ ^[Yy]$ ]]
}

select_config_mode() {
  if [[ "$SKIP_CONFIG" == "true" ]] || ! is_selected "cc-switch"; then
    return
  fi
  if ! has_tty; then
    return
  fi
  if ask_skip_config; then
    return
  fi
  if ask_webdav; then
    WEBDAV_IMPORT=true
  fi
}

### 本机安装检测 & 卸载逻辑 ###

NPM_ROOT_SYS=""
NPM_ROOT_USER=""

refresh_npm_roots() {
  NPM_ROOT_SYS=""
  NPM_ROOT_USER=""
  if command_exists npm; then
    if [[ "$(npm prefix -g 2>/dev/null)" == "$HOME"/* ]]; then
      NPM_ROOT_USER="$(npm root -g 2>/dev/null || true)"
    else
      NPM_ROOT_SYS="$(run_as_root npm root -g 2>/dev/null || true)"
    fi
  fi
}

is_pkg_installed() {
  local pkg="$1" bin="$2"
  if [[ -n "$NPM_ROOT_USER" && -d "${NPM_ROOT_USER}/${pkg}" ]]; then
    return 0
  fi
  if [[ -n "$NPM_ROOT_SYS" && -d "${NPM_ROOT_SYS}/${pkg}" ]]; then
    return 0
  fi
  command_exists "$bin"
}

detect_installed_tools() {
  if ! command_exists npm; then
    try_load_nvm || true
  fi
  refresh_npm_roots

  local i id pkg bin
  for i in "${!TOOL_IDS[@]}"; do
    id="${TOOL_IDS[$i]}"
    pkg="${TOOL_PKGS[$i]}"
    bin="${TOOL_BINS[$i]}"
    TOOL_INSTALLED[$i]=0
    if [[ -n "$pkg" ]]; then
      if is_pkg_installed "$pkg" "$bin"; then
        TOOL_INSTALLED[$i]=1
      fi
    elif [[ "$id" == "agy" ]]; then
      if [[ -e "$HOME/.local/bin/agy" ]] || command_exists agy; then
        TOOL_INSTALLED[$i]=1
      fi
    elif [[ "$id" == "cc-switch" ]]; then
      if [[ -e "$HOME/.local/bin/cc-switch" ]] || command_exists cc-switch; then
        TOOL_INSTALLED[$i]=1
      fi
    fi
  done
}

uninstall_one_npm_pkg() {
  local pkg="$1" bin="$2"
  echo "卸载 ${pkg} ..."

  # 同时检查用户级（nvm / prefix=$HOME）与系统级 npm，确保都能清干净
  if [[ -n "$NPM_ROOT_USER" && -d "${NPM_ROOT_USER}/${pkg}" ]]; then
    if ! npm uninstall -g "$pkg" 2>/dev/null; then
      rm -rf "${NPM_ROOT_USER}/${pkg}"
      echo "  已删除 ${NPM_ROOT_USER}/${pkg}"
    fi
  fi

  if [[ -n "$NPM_ROOT_SYS" && "$NPM_ROOT_SYS" != "$NPM_ROOT_USER" && -d "${NPM_ROOT_SYS}/${pkg}" ]]; then
    if ! run_as_root npm uninstall -g "$pkg" 2>/dev/null; then
      run_as_root rm -rf "${NPM_ROOT_SYS}/${pkg}"
      echo "  已删除 ${NPM_ROOT_SYS}/${pkg}"
    fi
  fi

  local bin_link
  for bin_link in "/usr/bin/${bin}" "/usr/local/bin/${bin}"; do
    if [[ -L "$bin_link" ]]; then
      run_as_root rm -f "$bin_link"
      echo "  已删除残留链接 ${bin_link}"
    fi
  done
}

clean_shell_rc_markers() {
  local f="$1" remove_cc="$2" remove_local="$3" remove_nvm="$4"
  [[ -f "$f" ]] || return 0
  local args=()
  [[ "$remove_cc" == "true" ]]    && args+=(-e '/# cc-switch/d')
  if [[ "$remove_local" == "true" ]]; then
    args+=(-e '/# local-bin/d' -e '/^# Added by Antigravity CLI installer$/{N;/\nexport PATH=.*\.local\/bin/d;}')
  fi
  [[ "$remove_nvm" == "true" ]]   && args+=(-e '/# nvm/d')
  if (( ${#args[@]} == 0 )); then
    return 0
  fi
  echo "清理 $f 中的相关条目 ..."
  sed -i "${args[@]}" "$f"
}

run_uninstall() {
  echo "=== 卸载 AI Harness / cc-switch-cli ==="
  echo

  detect_installed_tools
  TOOL_SELECTED=("${TOOL_INSTALLED[@]}")

  if [[ -n "$HARNESS_ARG" ]]; then
    if ! apply_tool_list "$HARNESS_ARG"; then
      exit 1
    fi
  elif has_tty; then
    tui_multiselect "请选择要卸载的工具（已自动预勾选本机已安装项）：" "true" "true"
  fi

  if (( $(selected_count) == 0 )); then
    echo "未选择任何卸载项，已退出。"
    exit 0
  fi

  if ! confirm_uninstall; then
    echo "已取消。"
    exit 0
  fi
  echo

  local i id pkg bin
  for i in "${!TOOL_IDS[@]}"; do
    [[ "${TOOL_SELECTED[$i]}" == "1" ]] || continue
    id="${TOOL_IDS[$i]}"
    pkg="${TOOL_PKGS[$i]}"
    bin="${TOOL_BINS[$i]}"

    if [[ -n "$pkg" ]]; then
      uninstall_one_npm_pkg "$pkg" "$bin"
    fi

    case "$id" in
      claude)
        rm -f "$HOME/.claude/settings.json" 2>/dev/null || true
        rmdir "$HOME/.claude" 2>/dev/null || true
        echo "  已清理 ~/.claude/settings.json"
        ;;
      codex)
        rm -rf "$HOME/.codex" 2>/dev/null || true
        echo "  已清理 ~/.codex"
        ;;
      agy)
        echo "卸载 Antigravity CLI (agy) ..."
        rm -f "$HOME/.local/bin/agy" 2>/dev/null || true
        rm -rf "$HOME/.cache/antigravity" 2>/dev/null || true
        echo "  已移除 ~/.local/bin/agy 与缓存（~/.gemini/antigravity-cli 已保留）"
        ;;
      cc-switch)
        echo "卸载 cc-switch-cli ..."
        rm -f "$HOME/.local/bin/cc-switch" 2>/dev/null || true
        rm -rf "$HOME/.local/share/cc-switch" 2>/dev/null || true
        rm -rf "$HOME/.local/share/cc-switch-cli" 2>/dev/null || true
        rm -rf "$HOME/.cc-switch" 2>/dev/null || true
        echo "  已移除 cc-switch-cli 与 ~/.cc-switch"
        ;;
    esac
  done

  # 刷新状态后再决定哪些 shell rc 标记可安全清理（避免部分卸载误删保留工具的环境）
  refresh_npm_roots
  local remove_cc="false" remove_local="false" remove_nvm="false"
  if is_selected "cc-switch" && [[ ! -e "$HOME/.local/bin/cc-switch" ]]; then
    remove_cc="true"
  fi
  if [[ ! -e "$HOME/.local/bin/agy" && ! -e "$HOME/.local/bin/cc-switch" ]]; then
    remove_local="true"
  fi
  if ! any_npm_tool_installed; then
    remove_nvm="true"
  fi

  SHELL_RC="$(detect_shell_rc)"
  if [[ -n "$SHELL_RC" ]]; then
    clean_shell_rc_markers "$SHELL_RC" "$remove_cc" "$remove_local" "$remove_nvm"
  fi
  for f in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.zshenv"; do
    if [[ "$f" != "$SHELL_RC" ]]; then
      clean_shell_rc_markers "$f" "$remove_cc" "$remove_local" "$remove_nvm"
    fi
  done

  echo
  if [[ -r "$PROXY_ENV_FILE" ]]; then
    echo "注：系统代理配置（${PROXY_ENV_FILE}）已保留；如需撤销可运行 proxy-init.sh --uninstall。"
  fi
  echo "卸载完成。"
  exit 0
}

### 安装逻辑 ###

install_distro_pkg() {
  local label="$1"
  shift
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  else
    echo "错误：无法检测 Linux 发行版（未找到 /etc/os-release）。" >&2
    exit 1
  fi

  local distro_id="${ID:-}"
  local distro_like="${ID_LIKE:-}"

  echo "未检测到 ${label}，开始安装 ..."

  if [[ "$distro_id" == "debian" || "$distro_id" == "ubuntu" || " $distro_like " == *" debian "* ]]; then
    run_as_root apt-get update
    run_as_root apt-get install -y "$@"
    return
  fi

  if [[ "$distro_id" == "arch" || " $distro_like " == *" arch "* ]]; then
    run_as_root pacman -Sy --noconfirm "$@"
    return
  fi

  if [[ "$distro_id" == "centos" || "$distro_id" == "rhel" || "$distro_id" == "rocky" || "$distro_id" == "almalinux" \
    || " $distro_like " == *" rhel "* || " $distro_like " == *" fedora "* ]]; then
    if command_exists dnf; then
      run_as_root dnf install -y "$@"
    elif command_exists yum; then
      run_as_root yum install -y "$@"
    else
      echo "错误：当前 CentOS/RHEL 系统中既没有 dnf，也没有 yum。" >&2
      exit 1
    fi
    return
  fi

  echo "错误：暂不支持当前 Linux 发行版：${distro_id:-unknown}。" >&2
  exit 1
}

ensure_curl() {
  command_exists curl && return 0
  install_distro_pkg "curl" curl ca-certificates
}

install_bubblewrap() {
  install_distro_pkg "bubblewrap" bubblewrap
}

install_npm_pkg() {
  local pkg="$1" rc
  echo "安装 ${pkg} ..."
  npm_run install -g "$pkg" && return 0
  rc=$?
  local pkg_dir
  pkg_dir="$(npm_run root -g)/${pkg}"
  if [[ -d "$pkg_dir" ]]; then
    echo "  npm install 失败 (exit ${rc})，可能是残留目录导致，清理后重试 ..."
    if [[ "$NVM_NODE" == "true" ]]; then
      rm -rf "$pkg_dir"
    else
      run_as_root rm -rf "$pkg_dir"
    fi
    npm_run install -g "$pkg"
  else
    return $rc
  fi
}

# 将 Antigravity CLI (~/.gemini/antigravity-cli/settings.json) 初始化为最高权限
configure_agy_permissions() {
  local cfg_dir="$HOME/.gemini/antigravity-cli"
  local cfg_file="${cfg_dir}/settings.json"
  mkdir -p "$cfg_dir"

  if [[ -s "$cfg_file" ]]; then
    local tmp_cfg
    tmp_cfg="$(mktemp "${cfg_dir}/.settings.XXXXXX.json")"
    if command_exists python3 && python3 -c "import json" >/dev/null 2>&1; then
      if AGY_CFG_JSON="$(cat "$cfg_file")" python3 - > "$tmp_cfg" <<'PY'
import json, os, sys

data = json.loads(os.environ["AGY_CFG_JSON"])
if not isinstance(data, dict):
    raise ValueError("settings root is not an object")

data["agentMode"] = "auto"
data["toolPermission"] = "always-proceed"
data["artifactReviewPolicy"] = "always-proceed"
data["allowNonWorkspaceAccess"] = True
data["enableTerminalSandbox"] = False

perms = data.get("permissions")
if not isinstance(perms, dict):
    perms = {}
allow = perms.get("allow")
if not isinstance(allow, list):
    allow = []
for rule in [
    "read_file(*)",
    "write_file(*)",
    "command(*)",
    "mcp(*)",
    "read_url(*)",
    "execute_url(*)",
    "download_url(*)",
]:
    if rule not in allow:
        allow.append(rule)
perms["allow"] = allow
data["permissions"] = perms

json.dump(data, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
PY
      then
        mv "$tmp_cfg" "$cfg_file"
      else
        rm -f "$tmp_cfg"
        echo "警告: 无法解析现有 ${cfg_file}，已保留原文件未修改。" >&2
        return 0
      fi
    elif command_exists node; then
      if AGY_CFG_JSON="$(cat "$cfg_file")" node - > "$tmp_cfg" <<'JS'
const data = JSON.parse(process.env.AGY_CFG_JSON);
if (!data || typeof data !== "object" || Array.isArray(data)) {
  throw new Error("settings root is not an object");
}
data.agentMode = "auto";
data.toolPermission = "always-proceed";
data.artifactReviewPolicy = "always-proceed";
data.allowNonWorkspaceAccess = true;
data.enableTerminalSandbox = false;
if (!data.permissions || typeof data.permissions !== "object" || Array.isArray(data.permissions)) {
  data.permissions = {};
}
if (!Array.isArray(data.permissions.allow)) {
  data.permissions.allow = [];
}
for (const rule of [
  "read_file(*)",
  "write_file(*)",
  "command(*)",
  "mcp(*)",
  "read_url(*)",
  "execute_url(*)",
  "download_url(*)",
]) {
  if (!data.permissions.allow.includes(rule)) {
    data.permissions.allow.push(rule);
  }
}
process.stdout.write(JSON.stringify(data, null, 2) + "\n");
JS
      then
        mv "$tmp_cfg" "$cfg_file"
      else
        rm -f "$tmp_cfg"
        echo "警告: 无法解析现有 ${cfg_file}，已保留原文件未修改。" >&2
        return 0
      fi
    else
      rm -f "$tmp_cfg"
      echo "警告: ${cfg_file} 已存在且未检测到 python3/node，跳过合并写入以避免覆盖原有配置。" >&2
      return 0
    fi
  else
    cat > "$cfg_file" <<'AGY_CFG_EOF'
{
  "agentMode": "auto",
  "toolPermission": "always-proceed",
  "artifactReviewPolicy": "always-proceed",
  "allowNonWorkspaceAccess": true,
  "enableTerminalSandbox": false,
  "permissions": {
    "allow": [
      "read_file(*)",
      "write_file(*)",
      "command(*)",
      "mcp(*)",
      "read_url(*)",
      "execute_url(*)",
      "download_url(*)"
    ]
  }
}
AGY_CFG_EOF
  fi

  echo "已将 Antigravity CLI 权限配置为最高级别（${cfg_file}）。"
}

install_agy() {
  echo "安装 Google Antigravity CLI (agy) ..."
  if [[ -x "$HOME/.local/bin/agy" ]]; then
    echo "检测到已有 $HOME/.local/bin/agy，跳过安装（agy 支持自动更新）。"
  else
    ensure_curl
    # 过滤 agy install 内部在 google.Init() 前调用 glog.Info 产生的无害 stderr 告警前缀
    { curl -fsSL https://antigravity.google/cli/install.sh | bash 2>&1 1>&3 | { grep -v '^ERROR: logging before google\.Init:' >&2 || true; }; } 3>&1
  fi
  configure_agy_permissions
}

apply_cc_switch_webdav_providers() {
  local cc_settings="$HOME/.cc-switch/settings.json"
  [[ -f "$cc_settings" ]] || return 0

  # cc-switch-cli 对单活动供应商工具在 settings.json 中保存 currentProvider<App>
  local pairs=(
    "claude:currentProviderClaude"
    "codex:currentProviderCodex"
    "gemini:currentProviderGemini"
    "opencode:currentProviderOpencode"
  )
  local pair app key provider_id
  for pair in "${pairs[@]}"; do
    app="${pair%%:*}"
    key="${pair#*:}"
    is_selected "$app" || continue
    provider_id="$(sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$cc_settings" 2>/dev/null | head -1 || true)"
    if [[ -n "$provider_id" ]]; then
      "$HOME/.local/bin/cc-switch" provider switch "$provider_id" --app "$app" 2>/dev/null || true
    fi
  done
}

install_cc_switch() {
  echo "安装 cc-switch-cli (SaladDay) ..."
  if [[ ! -x "$HOME/.local/bin/cc-switch" ]]; then
    ensure_curl
    export CC_SWITCH_FORCE=1
    curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash
  fi

  configure_shell_env "cc-switch"

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
      apply_cc_switch_webdav_providers
      echo "WebDAV 配置导入完成。"
    else
      echo "警告: WebDAV 配置拉取失败，请检查网络连接和凭据后重试。"
    fi
  fi
}

print_summary() {
  echo
  echo "已安装："
  local i id
  for i in "${!TOOL_IDS[@]}"; do
    [[ "${TOOL_SELECTED[$i]}" == "1" ]] || continue
    id="${TOOL_IDS[$i]}"
    if [[ -n "${TOOL_PKGS[$i]}" ]]; then
      echo "  - ${TOOL_PKGS[$i]} (${id})"
    elif [[ "$id" == "agy" ]]; then
      echo "  - Antigravity CLI (agy)"
    elif [[ "$id" == "cc-switch" ]]; then
      echo "  - cc-switch-cli (cc-switch)"
    fi
  done

  echo
  echo "提示：运行 source $SHELL_RC 或重新打开终端以使 PATH 生效。"
  if is_selected "cc-switch"; then echo "      运行 cc-switch 可切换 Claude / Codex / Gemini / OpenCode / Pi 的 provider。"; fi
  if is_selected "claude"; then    echo "      运行 claude 可启动 Claude Code。"; fi
  if is_selected "codex"; then     echo "      运行 codex 可启动 Codex。"; fi
  if is_selected "dsh"; then       echo "      运行 dsh web（或 dsh）可启动 DeepSeek Harness。"; fi
  if is_selected "agy"; then       echo "      运行 agy 可启动 Antigravity CLI。"; fi
  if is_selected "grok"; then      echo "      运行 grok 可启动 Grok Build。"; fi
  if is_selected "gemini"; then    echo "      运行 gemini 可启动 Gemini CLI。"; fi
  if is_selected "opencode"; then  echo "      运行 opencode 可启动 OpenCode。"; fi
  if is_selected "pi"; then        echo "      运行 pi 可启动 Pi Coding Agent。"; fi

  if is_selected "dsh" || is_selected "agy" || is_selected "grok"; then
    echo "注：cc-switch-cli 暂不支持管理 dsh / agy / grok，这几款工具请按各自方式登录或配置 API Key。"
  fi
}

# 从短链优先拉取 proxy-init.sh，失败时回退到 GitHub raw
download_proxy_init() {
  local dest="$1"
  echo "正在拉取 proxy-init.sh (${PROXY_INIT_URL}) ..."
  if curl -fsSL --connect-timeout 10 "$PROXY_INIT_URL" -o "$dest"; then
    return 0
  fi
  echo "短链拉取失败，尝试从 GitHub 回退地址拉取 ..." >&2
  curl -fsSL --connect-timeout 15 "$PROXY_INIT_FALLBACK_URL" -o "$dest"
}

run_proxy_init_script() {
  local script_path="$1"
  shift
  if has_tty; then
    run_as_root bash "$script_path" "$@" </dev/tty
  else
    run_as_root bash "$script_path" "$@" </dev/null
  fi
}

# 安装前按需调用 proxy-init 配置系统代理，并立即导入当前进程环境
configure_proxy_before_install() {
  local ans="" existing_proxy=""
  if [[ -z "$PROXY_ARG" ]]; then
    if [[ -n "$HARNESS_ARG" ]] || ! has_tty; then
      return 0
    fi
    if [[ -r "$PROXY_ENV_FILE" ]]; then
      existing_proxy="$(sed -n 's/^PROXY_URL="\(.*\)"/\1/p' "$PROXY_ENV_FILE" 2>/dev/null | head -1 || true)"
    fi
    if [[ -n "$existing_proxy" ]]; then
      read -rp "检测到已有系统代理 (${existing_proxy})，是否重新配置？[y/N]: " ans </dev/tty
    else
      read -rp "是否需要在安装前配置系统代理 (proxy-init)？[y/N]: " ans </dev/tty
    fi
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      return 0
    fi
    echo
  fi

  ensure_curl

  local tmp_proxy
  tmp_proxy="$(mktemp "${TMPDIR:-/tmp}/proxy-init.XXXXXX.sh")"
  if ! download_proxy_init "$tmp_proxy"; then
    rm -f "$tmp_proxy"
    echo "错误: 无法拉取 proxy-init.sh。" >&2
    if [[ -n "$PROXY_ARG" ]] || ! has_tty; then
      exit 1
    fi
    read -rp "是否跳过代理配置继续安装？[y/N]: " ans </dev/tty
    [[ "$ans" =~ ^[Yy]$ ]] && return 0
    exit 1
  fi

  local proxy_args=()
  if [[ ! -d /etc/apt/apt.conf.d ]]; then
    proxy_args+=(--no-apt)
  fi
  if [[ -n "$PROXY_ARG" ]]; then
    proxy_args+=(--proxy "$PROXY_ARG")
  fi

  local ok=false
  while true; do
    if run_proxy_init_script "$tmp_proxy" "${proxy_args[@]}"; then
      ok=true
      break
    fi
    if [[ -n "$PROXY_ARG" ]] || ! has_tty; then
      break
    fi
    read -rp "代理配置未成功，是否重试？[y/N]: " ans </dev/tty
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      continue
    fi
    read -rp "是否跳过代理配置继续安装？[y/N]: " ans </dev/tty
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      rm -f "$tmp_proxy"
      return 0
    fi
    rm -f "$tmp_proxy"
    exit 1
  done

  rm -f "$tmp_proxy"
  if [[ "$ok" != "true" ]]; then
    echo "错误: 系统代理配置失败。" >&2
    exit 1
  fi

  if [[ -r "$PROXY_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$PROXY_ENV_FILE"
  fi
  echo
}

main() {
  parse_args "$@"

  if [[ "$ACTION" == "uninstall" ]]; then
    run_uninstall
  fi

  configure_proxy_before_install

  select_tools_for_install
  select_config_mode

  SHELL_RC="$(detect_shell_rc)"

  if needs_node; then
    local req_ver min_major min_minor
    req_ver="$(required_node_version)"
    min_major="${req_ver%% *}"
    min_minor="${req_ver##* }"
    if ! node_version_ok "$min_major" "$min_minor"; then
      install_nvm_node
      NVM_NODE=true
      echo
    fi
  fi

  if needs_bwrap && ! command_exists bwrap; then
    install_bubblewrap
  fi

  if needs_local_bin_path; then
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"
  fi

  local i id pkg
  for i in "${!TOOL_IDS[@]}"; do
    [[ "${TOOL_SELECTED[$i]}" == "1" ]] || continue
    id="${TOOL_IDS[$i]}"
    pkg="${TOOL_PKGS[$i]}"
    if [[ -n "$pkg" ]]; then
      install_npm_pkg "$pkg"
    elif [[ "$id" == "agy" ]]; then
      install_agy
    elif [[ "$id" == "cc-switch" ]]; then
      install_cc_switch
    fi
  done

  if ! is_selected "cc-switch" && is_selected "agy"; then
    configure_shell_env "local-bin"
  fi

  print_summary
}

main "$@"
