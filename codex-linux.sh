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

WEBDAV_IMPORT=false
NVM_NODE=false
NVM_DIR="$HOME/.nvm"
NVM_VERSION="v0.40.7"

# 检测 npm 可用且 Node ≥ 22.0.0；满足则直接用现有环境，不装 nvm
node_version_ok() {
  command_exists npm || return 1
  command_exists node || return 1
  local major
  major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)" || return 1
  [[ "$major" =~ ^[0-9]+$ ]] || return 1
  (( major >= 22 ))
}

# 通过 nvm 安装 Node 24 LTS（无 npm 或 Node < 22 时的路径）
install_nvm_node() {
  echo "未检测到可用的 Node.js (>= 22)，通过 nvm 安装 Node 24 LTS ..."

  # 1) 安装 nvm（tarball 方式，只需 curl + tar，不依赖 git）
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo "安装 nvm ${NVM_VERSION} ..."
    if ! command_exists curl; then
      echo "错误: 安装 nvm 需要 curl。" >&2
      exit 1
    fi
    mkdir -p "$NVM_DIR"
    if ! curl -fsSL "https://github.com/nvm-sh/nvm/archive/refs/tags/${NVM_VERSION}.tar.gz" | \
      tar -xz --strip-components=1 -C "$NVM_DIR"; then
      echo "错误: nvm 安装失败，无法继续。" >&2
      exit 1
    fi
  else
    echo "检测到已有 nvm，跳过安装。"
  fi

  # 2) 加载 nvm（非交互 shell 中 nvm 默认不生效，必须显式 source）
  export NVM_DIR
  # shellcheck disable=SC1091
  . "$NVM_DIR/nvm.sh"

  # 3) 安装 Node 24 LTS 并设为默认
  nvm install 24
  nvm alias default 24 >/dev/null
  echo "已激活 Node $(node -v)。"

  # 4) 写入 nvm 加载段到 shell rc（幂等；'# nvm' 标记便于卸载时清理）
  if [[ -n "$SHELL_RC" ]] && ! grep -q '# nvm' "$SHELL_RC" 2>/dev/null; then
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

# npm 执行封装：nvm 场景用户级运行，否则 sudo 运行
# npm 执行封装：nvm 或用户级 npm 直接运行，系统级 npm 用 sudo
# （注意：sudo 使用系统 secure_path，看不到 nvm/用户路径下的 npm，
#  因此必须按 npm 全局安装位置来决定是否 sudo，而不是仅凭当前 PATH 可见）
npm_run() {
  if [[ "$NVM_NODE" == "true" ]] \
    || { command_exists npm && [[ "$(npm prefix -g 2>/dev/null)" == "$HOME"/* ]]; }; then
    npm "$@"
  else
    run_as_root npm "$@"
  fi
}

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

# 确保 login shell 也能加载 cc-switch 相关环境变量。
# Bash login shell 的加载顺序：~/.bash_profile -> ~/.bash_login -> ~/.profile（取第一个存在的）
# 而 ~/.bashrc 仅对 non-login interactive shell 生效。
# 在 LXC 容器中通过 pct enter / SSH 登录都是 login shell，可能完全不 source ~/.bashrc。
write_profile_guard() {
  # 只有 bash 用户需要这个兜底
  if is_fish_rc "$SHELL_RC"; then
    return 0
  fi

  local bash_profile="$HOME/.bash_profile"
  local profile="$HOME/.profile"

  # 1) 如果 ~/.bash_profile 已存在，追加到其中
  if [[ -f "$bash_profile" ]]; then
    if ! grep -q '# cc-switch' "$bash_profile" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"  # cc-switch' >> "$bash_profile"
      echo 'export IS_SANDBOX=1  # cc-switch' >> "$bash_profile"
    fi
    return 0
  fi

  # 2) 如果 ~/.profile 已存在，追加到其中
  if [[ -f "$profile" ]]; then
    if ! grep -q '# cc-switch' "$profile" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"  # cc-switch' >> "$profile"
      echo 'export IS_SANDBOX=1  # cc-switch' >> "$profile"
    fi
    return 0
  fi

  # 3) 两者都不存在（极端情况：最小化 LXC 容器）：创建 ~/.bash_profile
  #    使其 source ~/.bashrc 和 ~/.profile（如果将来创建），并写入环境变量
  cat > "$bash_profile" <<'PROFILE_EOF'
# ~/.bash_profile — created by codex installer (cc-switch)

if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi

if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

export PATH="$HOME/.local/bin:$PATH"  # cc-switch
export IS_SANDBOX=1  # cc-switch
PROFILE_EOF
}

### 用户交互 ###

# 选择跳过配置则返回 0（[y/N] 默认 N：回车或非 y 均不跳过）
ask_skip_config() {
  read -rp "跳过配置 API Key 和 URL？[y/N]: " SKIP_ANSWER
  [[ "$SKIP_ANSWER" =~ ^[Yy]$ ]]
}

# 选择 WebDAV 导入则返回 0，并读取凭据（[y/N] 默认 N：回车或非 y 均不导入）
ask_webdav() {
  read -rp "从 WebDAV 导入 cc-switch 配置？[y/N]: " WEBDAV_ANSWER
  [[ "$WEBDAV_ANSWER" =~ ^[Yy]$ ]] || return 1
  read -rp "WebDAV Base URL: " WEBDAV_URL
  read -rp "WebDAV Username: " WEBDAV_USER
  read -rsp "WebDAV Password: " WEBDAV_PASS
  echo
}

# 选择卸载则返回 0（[y/N] 默认 N）
confirm_uninstall() {
  read -rp "确认卸载？将删除所有相关工具和配置文件 [y/N]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]]
}

# 决定是否导入配置：
#   --skip-config / 选择跳过 / 拒绝导入 → 直接安装（不导入配置）
#   选择 WebDAV 导入 → WEBDAV_IMPORT=true，稍后从云端拉取并应用配置
select_config_mode() {
  if [[ "${1:-}" == "--skip-config" ]]; then
    return
  fi
  if ask_skip_config; then
    return
  fi
  if ask_webdav; then
    WEBDAV_IMPORT=true
  fi
}

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "=== 卸载 Codex / Claude Code / cc-switch-cli ==="
  echo

  if ! confirm_uninstall; then
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
    # 系统无 npm：包可能装在 nvm 里，尝试通过 nvm 卸载（用户级，无需 sudo）
    echo "npm 未找到，尝试通过 nvm 卸载 ..."
    if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
      export NVM_DIR="$HOME/.nvm"
      # shellcheck disable=SC1091
      . "$NVM_DIR/nvm.sh"
      if nvm which default >/dev/null 2>&1; then
        # use 失败不中止脚本：后续 npm 不可用时走 rm -rf 兜底
        nvm use default >/dev/null 2>&1 || true
        for pkg in "@openai/codex" "@anthropic-ai/claude-code"; do
          echo "卸载 ${pkg} ..."
          if ! npm uninstall -g "$pkg" 2>/dev/null; then
            echo "  npm 卸载失败，直接删除文件 ..."
            pkg_dir="$(npm root -g 2>/dev/null || true)/${pkg}"
            if [[ -d "$pkg_dir" ]]; then
              rm -rf "$pkg_dir"
              echo "  已删除 ${pkg_dir}"
            else
              echo "  (跳过，未找到 ${pkg_dir})"
            fi
          fi
        done
      else
        echo "  (nvm 中没有 default 版本，跳过)"
      fi
      unset NVM_DIR
    else
      echo "  (未找到 ~/.nvm，跳过)"
    fi
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
    sed -i -e '/# cc-switch/d' -e '/# nvm/d' "$SHELL_RC"
    echo "  已清理。"
  fi

  # 也清理 ~/.profile 和 ~/.bash_profile 中的兜底条目
  for f in "$HOME/.profile" "$HOME/.bash_profile"; do
    if [[ -f "$f" ]]; then
      echo "清理 $f 中的相关条目 ..."
      sed -i -e '/# cc-switch/d' -e '/# nvm/d' "$f"
      echo "  已清理。"
    fi
  done

  echo
  echo "卸载完成。"
  exit 0
fi

select_config_mode

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

# 已有 npm 且 Node ≥ 22 时直接用现有环境；否则用 nvm 安装 Node 24 LTS
if ! node_version_ok; then
  install_nvm_node
  NVM_NODE=true
  echo
fi

if ! command_exists bwrap; then
  install_bubblewrap
fi

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

install_npm_pkg @openai/codex
install_npm_pkg @anthropic-ai/claude-code

echo "安装 cc-switch-cli (SaladDay) ..."
# 检查二进制文件是否存在，而非检查 PATH（避免 PATH 未包含 ~/.local/bin 时重复安装）
if [[ ! -x "$HOME/.local/bin/cc-switch" ]]; then
  export CC_SWITCH_FORCE=1
  curl -fsSL https://github.com/SaladDay/cc-switch-cli/releases/latest/download/install.sh | bash
  # 确保 cc-switch 在当前会话中可用
  export PATH="$HOME/.local/bin:$PATH"
  if ! grep -q '# cc-switch' "$SHELL_RC" 2>/dev/null; then
    if is_fish_rc "$SHELL_RC"; then
      echo 'set -gx PATH "$HOME/.local/bin" $PATH  # cc-switch' >> "$SHELL_RC"
    else
      echo 'export PATH="$HOME/.local/bin:$PATH"  # cc-switch' >> "$SHELL_RC"
    fi
  fi
else
  # 二进制已安装但 PATH 可能缺 ~/.local/bin，补上
  export PATH="$HOME/.local/bin:$PATH"
fi

# 将 IS_SANDBOX=1 尽早写入，避免后续任何步骤失败导致遗漏
if ! grep -q 'IS_SANDBOX=1' "$SHELL_RC" 2>/dev/null; then
  if is_fish_rc "$SHELL_RC"; then
    echo 'set -gx IS_SANDBOX 1  # cc-switch' >> "$SHELL_RC"
  else
    echo 'export IS_SANDBOX=1  # cc-switch' >> "$SHELL_RC"
  fi
fi
export IS_SANDBOX=1  # 当前会话也立即生效

# 兜底：确保 login shell 也能获得环境变量（LXC 容器中 ~/.profile 可能不 source ~/.bashrc）
write_profile_guard

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

echo "已安装："
echo "  - @openai/codex"
echo "  - @anthropic-ai/claude-code"
echo "  - cc-switch-cli"
echo
echo "提示：运行 source $SHELL_RC 或重新打开终端以使 PATH 生效。"
echo "      运行 cc-switch 可切换 Claude Code 的不同 provider。"
echo "      运行 claude 可启动 Claude Code。"
