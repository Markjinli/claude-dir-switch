#!/usr/bin/env bash
# ============================================================
#  Claude Code 全家桶 — Mac 一键安装脚本
#  真正固定头部 + 可见下载进度 + 错误重试 + 自动环境变量
# ============================================================

# 严格模式（但在重试块内临时关闭 pipefail）
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

START_TIME=$(date +%s)
LOG_FILE="/tmp/claude-tools-install-$$.log"
SCROLL_LINES=()
CURRENT_STEP=0
TOTAL_STEPS=5
CURRENT_LABEL=""
HEADER_LINES=10

# ── 终端控制 ──
term_rows()  { tput lines 2>/dev/null || echo 40; }
term_cols()  { tput cols 2>/dev/null || echo 80; }
hide_cursor(){ printf '\033[?25l'; }
show_cursor(){ printf '\033[?25h'; }

add_log() {
    local emoji="$1" text="$2"
    local ts; ts=$(date +%H:%M:%S)
    SCROLL_LINES+=("$(printf "  %s ${DIM}%s${NC} %s" "$emoji" "$ts" "$text")")
    echo "[$(date '+%H:%M:%S')] $text" >> "$LOG_FILE"
}
log()  { add_log "✓" "$1"; }
warn() { add_log "⚠" "$1"; }
err()  { add_log "✗" "$1"; }
info() { add_log "→" "$1"; }

# ── 绘制固定头部（只会画在屏幕顶部，不依赖滚动区）──
draw_header() {
    local step=$1 total=$2 label="$3"
    # 临时退出滚动区域，画到全屏
    tput csr 0 "$(term_rows)" 2>/dev/null || true
    printf '\033[H'  # cursor home

    printf "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}${BOLD}  ║${NC}     Claude Code 全家桶 — Mac 一键安装           ${CYAN}${BOLD}║${NC}\n"
    printf "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "  ${DIM}▸ Homebrew   ▸ Node.js   ▸ Claude Code   ▸ CC-Switch   ▸ CloudCLI${NC}\n"
    printf "\n"

    # 进度条
    local width=36
    local filled=$(( step * width / (total > 0 ? total : 1) ))
    local empty=$(( width - filled ))
    local bar_filled bar_empty pct
    bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '█')
    bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')
    pct=$(( step * 100 / (total > 0 ? total : 1) ))

    local elapsed=$(($(date +%s) - START_TIME))
    printf "  ${BOLD}${BLUE}%s%s${NC} ${BOLD}%d%%${NC}  ${DIM}%d/%d${NC}" \
        "$bar_filled" "$bar_empty" "$pct" "$step" "$total"
    printf "  ${DIM}已用 %ds${NC}\n" "$elapsed"

    printf "  ${CYAN}→ %s${NC}\n" "$label"
    printf "  ${DIM}──────────────────────────────────────────────────${NC}\n"

    # 重新设置滚动区域为头部下方
    tput csr "$HEADER_LINES" "$(term_rows)" 2>/dev/null || true
}

# ── 滚动日志区（只在可滚动区域内绘制）──
draw_scroll_area() {
    local rows scroll_start max_visible total_logs start_idx i
    rows=$(term_rows)
    scroll_start=$((HEADER_LINES + 1))

    # 移到滚动区域起始位置
    printf '\033[%d;0H' "$scroll_start"
    # 清除头部以下
    printf '\033[J'

    max_visible=$((rows - HEADER_LINES - 2))
    total_logs=${#SCROLL_LINES[@]}
    start_idx=0
    if (( total_logs > max_visible )); then
        start_idx=$((total_logs - max_visible))
    fi

    for ((i = start_idx; i < total_logs; i++)); do
        printf "%s\n" "${SCROLL_LINES[$i]}"
    done
}

# ── 带重试的网络操作 ──
retry() {
    local max_attempts=3 desc="$1"; shift
    local attempt=1 delay=3
    while (( attempt <= max_attempts )); do
        if "$@"; then
            return 0
        fi
        local rc=$?
        warn "[尝试 ${attempt}/${max_attempts}] ${desc} 失败 (exit=${rc})"
        if (( attempt < max_attempts )); then
            info "等待 ${delay} 秒后重试..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done
    err "${desc} 失败 ${max_attempts} 次，请检查网络后重新运行脚本"
    return 1
}

# ── 安装 brew cask 的包装（带重试）──
brew_install() {
    local pkg="$1" desc="$2" type="${3:-formula}"
    info "正在安装 ${desc}..."

    if [[ "$type" == "cask" ]]; then
        retry "$desc" brew install --cask "$pkg"
    else
        retry "$desc" brew install "$pkg"
    fi
}

# ── shell 配置检测 ──
detect_profile() {
    case "${SHELL##*/}" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bash_profile" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

persist_path() {
    local dir="$1" profile
    profile=$(detect_profile)
    if [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$dir:$PATH"
    fi
    if ! grep -qF "$dir" "$profile" 2>/dev/null; then
        printf '\n# Added by Claude Tools installer\nexport PATH="%s:$PATH"\n' "$dir" >> "$profile"
    fi
}

# ═══════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════

if [[ "$(uname)" != "Darwin" ]]; then
    echo "本脚本仅支持 macOS，当前系统: $(uname)" && exit 1
fi

trap 'tput csr 0 $(term_rows) 2>/dev/null; show_cursor; exit 1' INT TERM
trap 'tput csr 0 $(term_rows) 2>/dev/null; show_cursor' EXIT

hide_cursor
printf '\033[2J\033[H'

# 设置滚动区域：头部以下可滚动
tput csr "$HEADER_LINES" "$(term_rows)" 2>/dev/null || true

draw_header 0 "$TOTAL_STEPS" "初始化..."
draw_scroll_area

PROFILE=$(detect_profile)

# ═══════════════════════════════
# Step 0: sudo — 先清除提示输入密码
# ═══════════════════════════════
printf '\n'
printf "  ${YELLOW}${BOLD}请输入你的 Mac 开机密码，然后按回车:${NC}\n"
printf '\n'

if sudo -v; then
    log "密码验证成功，权限已缓存"
    # 后台持续续期
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || break; done 2>/dev/null &
    SUDO_KEEPER_PID=$!
else
    err "密码验证失败，请重新运行脚本"
    show_cursor
    exit 1
fi

# ═══════════════════════════════
# Step 1: Homebrew + Node.js + PATH
# ═══════════════════════════════
CURRENT_STEP=1
CURRENT_LABEL="安装 Homebrew + Node.js + 配置环境变量"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

# ── Homebrew ──
if command -v brew &>/dev/null; then
    log "Homebrew 已安装 — $(brew --version | head -1)"
else
    info "正在安装 Homebrew（下载速度可见下方）..."
    # 临时解除 pipefail，让 Homebrew 安装不会因 tee 退出码而中断
    set +o pipefail
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL --retry 3 --retry-delay 5 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        </dev/null 2>&1
    local brew_rc=$?
    set -o pipefail

    if (( brew_rc == 0 )) && command -v brew &>/dev/null; then
        log "Homebrew 安装完成"
    else
        err "Homebrew 安装失败 (exit=${brew_rc})"
        err "常见原因: 网络不通、DNS 问题。请检查是否可访问 github.com"
        err "尝试手动安装: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        show_cursor
        exit 1
    fi
fi

# 检测路径
if [[ -f /opt/homebrew/bin/brew ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -f /usr/local/bin/brew ]]; then
    HOMEBREW_PREFIX="/usr/local"
else
    err "无法找到 Homebrew 安装路径"
    show_cursor; exit 1
fi
eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"

# ── 写入 .zprofile ──
if ! grep -q "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
    cat >> "$HOME/.zprofile" << BREWEOF

# Homebrew — added by Claude Tools installer
eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
BREWEOF
    log "eval \"\$(brew shellenv)\" 已写入 ~/.zprofile"
else
    log "Homebrew 环境已存在于 ~/.zprofile"
fi

if ! grep -q "brew shellenv" "$PROFILE" 2>/dev/null; then
    printf '\n# Homebrew\neval "$(%s/bin/brew shellenv)"\n' "$HOMEBREW_PREFIX" >> "$PROFILE"
fi

# ── Node.js ──
NEED_NODE=false
if ! command -v node &>/dev/null; then
    NEED_NODE=true
elif [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 18 ]]; then
    NEED_NODE=true
    warn "Node.js 版本过低 ($(node -v))，需要 >= 18"
fi

if $NEED_NODE; then
    brew_install node "Node.js"
    log "Node.js $(node -v) (npm $(npm -v)) 安装完成"
else
    log "Node.js 已安装 — $(node -v)"
fi

# ── PATH ──
mkdir -p "$HOME/.local/bin"
persist_path "$HOME/.local/bin"
NPM_BIN=""
if command -v npm &>/dev/null; then
    NPM_BIN=$(npm config get prefix 2>/dev/null)/bin
    if [[ -d "$NPM_BIN" ]] && [[ "$NPM_BIN" != "/usr/bin" ]]; then
        persist_path "$NPM_BIN"
    fi
fi
log "PATH 环境变量已写入 ${PROFILE}"

# ═══════════════════════════════
# Step 2: Claude Code
# ═══════════════════════════════
CURRENT_STEP=2
CURRENT_LABEL="安装 Claude Code"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if command -v claude &>/dev/null; then
    log "Claude Code 已安装 — $(claude --version 2>/dev/null || echo 'ok')"
else
    TMP_INSTALL="/tmp/claude-install-$$.sh"
    info "正在下载 Claude Code 安装脚本..."

    set +o pipefail
    curl -# --retry 3 --retry-delay 5 -fSL \
        "https://claude.ai/install.sh" -o "$TMP_INSTALL" 2>&1
    local curl_rc=$?
    set -o pipefail

    if (( curl_rc != 0 )) || [[ ! -s "$TMP_INSTALL" ]]; then
        warn "官方脚本下载失败 (exit=${curl_rc})，尝试 Homebrew cask..."
        brew_install "claude-code@latest" "Claude Code" "cask"
        log "Claude Code (brew) 安装完成"
    else
        info "正在执行安装..."
        set +o pipefail
        bash "$TMP_INSTALL" 2>&1
        local install_rc=$?
        set -o pipefail
        rm -f "$TMP_INSTALL"

        if (( install_rc == 0 )) && command -v claude &>/dev/null; then
            log "Claude Code 安装完成"
        else
            warn "官方脚本安装失败 (exit=${install_rc})，尝试 Homebrew cask..."
            brew_install "claude-code@latest" "Claude Code" "cask"
            log "Claude Code (brew) 安装完成"
        fi
    fi
fi

# ═══════════════════════════════
# Step 3: CC-Switch
# ═══════════════════════════════
CURRENT_STEP=3
CURRENT_LABEL="安装 CC-Switch"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if [[ -d "/Applications/CC-Switch.app" ]]; then
    log "CC-Switch 已安装"
else
    info "添加 CC-Switch 软件源..."
    brew tap farion1231/ccswitch 2>> "$LOG_FILE" || true
    brew_install "cc-switch" "CC-Switch" "cask"
    if [[ -d "/Applications/CC-Switch.app" ]]; then
        log "CC-Switch 安装完成 → /Applications/CC-Switch.app"
    else
        warn "CC-Switch 未出现在 /Applications，请手动下载:"
        warn "https://github.com/farion1231/cc-switch/releases"
    fi
fi

# ═══════════════════════════════
# Step 4: CloudCLI
# ═══════════════════════════════
CURRENT_STEP=4
CURRENT_LABEL="安装 CloudCLI (网页版 UI)"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

CLOUDCLI_BIN="$HOME/.local/bin/cloudcli"
mkdir -p "$HOME/.local/bin"
cat > "$CLOUDCLI_BIN" << 'CLOUDCLI_SCRIPT'
#!/usr/bin/env bash
echo "🚀 正在启动 Claude Code UI..."
echo "   浏览器打开 → http://localhost:3000"
exec npx @cloudcli-ai/cloudcli "$@"
CLOUDCLI_SCRIPT
chmod +x "$CLOUDCLI_BIN"
log "cloudcli 命令已创建: $CLOUDCLI_BIN"

# ═══════════════════════════════
# Step 5: 完成
# ═══════════════════════════════
CURRENT_STEP=5
CURRENT_LABEL="安装完成!"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

# 清理
if [[ -n "${SUDO_KEEPER_PID:-}" ]]; then
    kill "$SUDO_KEEPER_PID" 2>/dev/null || true
fi
log "sudo 权限缓存已释放"
hash -r 2>/dev/null || true

# 恢复滚动区域
tput csr 0 "$(term_rows)" 2>/dev/null || true
show_cursor

# 最终报告
printf '\033[2J\033[H'
ELAPSED=$(($(date +%s) - START_TIME))
echo ""
echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}  ║          ✅  安装完成!  (耗时 ${ELAPSED}s)              ║${NC}"
echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}已安装的工具:${NC}"
printf "  %-20s → 终端输入 ${BOLD}%s${NC}\n" "Claude Code" "claude"
printf "  %-20s → ${BOLD}%s${NC}\n" "CC-Switch" "/Applications/CC-Switch.app"
printf "  %-20s → 终端输入 ${BOLD}%s${NC}\n" "CloudCLI (网页UI)" "cloudcli"
echo ""
echo -e "  ${BOLD}环境变量已写入:${NC}"
printf "  %-24s → ${CYAN}%s${NC}\n" "Homebrew shellenv" "~/.zprofile"
printf "  %-24s → ${CYAN}%s${NC}\n" "Homebrew (备用)" "$PROFILE"
printf "  %-24s → ${CYAN}%s${NC}\n" "~/.local/bin PATH" "$PROFILE"
if [[ -n "${NPM_BIN:-}" ]]; then
    printf "  %-24s → ${CYAN}%s${NC}\n" "npm global bin" "$PROFILE"
fi
echo ""
echo -e "  ${YELLOW}${BOLD}⚠ 运行以下命令使环境变量立即生效:${NC}"
echo -e "  ${CYAN}source ~/.zprofile && source ${PROFILE}${NC}"
echo ""
echo -e "  ${BOLD}下一步:${NC}"
echo "  1. 打开 CC-Switch.app 添加 API Key"
echo "  2. 或终端输入 claude 进行 OAuth 登录"
echo "  3. 终端输入 cloudcli 启动网页版 UI"
echo ""
echo -e "  ${DIM}安装日志: ${LOG_FILE}${NC}"
echo ""
