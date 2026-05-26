#!/usr/bin/env bash
# ============================================================
#  Claude Code 全家桶 — Mac 一键安装脚本
#  分屏 UI · 下载进度可见 · 自动环境变量配置
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

TOTAL_STEPS=5
CURRENT_STEP=0
START_TIME=$(date +%s)
SCROLL_LINES=()
HEADER_LINES=11
LOG_FILE="/tmp/claude-tools-install-$$.log"

# ── 终端控制 ──
clear_screen()  { printf '\033[2J\033[H'; }
cursor_home()   { printf '\033[H'; }
cursor_to()     { printf '\033[%d;%dH' "$1" "$2"; }
clear_to_end()  { printf '\033[J'; }
clear_line()    { printf '\033[K'; }
hide_cursor()   { printf '\033[?25l'; }
show_cursor()   { printf '\033[?25h'; }
term_rows()     { tput lines 2>/dev/null || echo 40; }

add_log() {
    local emoji="$1" text="$2"
    local ts; ts=$(date +%H:%M:%S)
    SCROLL_LINES+=("$(printf "  ${emoji} ${DIM}%s${NC} %s" "$ts" "$text")")
    echo "[$(date '+%H:%M:%S')] $text" >> "$LOG_FILE"
}

log()  { add_log "✓" "$1"; }
warn() { add_log "⚠" "$1"; }
err()  { add_log "✗" "$1"; }
info() { add_log "→" "$1"; }

draw_header() {
    local step=$1 total=$2 label="$3"
    cursor_home

    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║${NC}     Claude Code 全家桶 — Mac 一键安装           ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${DIM}▸ Homebrew   ▸ Node.js   ▸ Claude Code   ▸ CC-Switch   ▸ CloudCLI${NC}"
    echo ""

    local width=36
    local filled=$(( step * width / total ))
    local empty=$(( width - filled ))
    local bar_filled bar_empty pct
    bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '█')
    bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')
    pct=$(( step * 100 / total ))

    local elapsed=$(($(date +%s) - START_TIME))
    printf "  ${BOLD}${BLUE}%s%s${NC} ${BOLD}%d%%${NC}  ${DIM}%d/%d${NC}" \
        "$bar_filled" "$bar_empty" "$pct" "$step" "$total"
    printf "  ${DIM}已用 %ds${NC}\n" "$elapsed"

    echo -e "  ${CYAN}→ %s${NC}" "$label"
    echo -e "  ${DIM}──────────────────────────────────────────────────${NC}"
}

draw_scroll_area() {
    local rows scroll_start max_visible total_logs start_idx i
    rows=$(term_rows)
    scroll_start=$((HEADER_LINES + 1))
    cursor_to "$scroll_start" 0
    clear_to_end

    max_visible=$((rows - HEADER_LINES - 2))
    total_logs=${#SCROLL_LINES[@]}
    start_idx=0
    if (( total_logs > max_visible )); then
        start_idx=$((total_logs - max_visible))
    fi

    for ((i = start_idx; i < total_logs; i++)); do
        echo -e "${SCROLL_LINES[$i]}"
        clear_line
    done
}

# 在长命令执行前：移动光标到滚动区域底部，输出自然显示
pre_cmd() {
    local rows; rows=$(term_rows)
    cursor_to "$rows" 0
}

# 长命令执行后：重绘整个 UI
post_cmd() {
    draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
    draw_scroll_area
}

CURRENT_LABEL=""

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
    if ! grep -qF "$dir" "$profile" 2>/dev/null && \
       ! grep -qF "export PATH=\"$dir:" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# Added by Claude Tools installer" >> "$profile"
        echo "export PATH=\"$dir:\$PATH\"" >> "$profile"
    fi
}

# ═══════════════════════════════════════════
# 开始
# ═══════════════════════════════════════════

if [[ "$(uname)" != "Darwin" ]]; then
    echo "本脚本仅支持 macOS，当前系统: $(uname)" && exit 1
fi

trap 'show_cursor; exit 1' INT TERM
trap 'show_cursor' EXIT

hide_cursor
clear_screen
draw_header 0 "$TOTAL_STEPS" "初始化..."
draw_scroll_area
PROFILE=$(detect_profile)

# ═══════════════════════════════
# Step 0: sudo
# ═══════════════════════════════
info "请求管理员权限..."
if sudo -v; then
    log "密码验证成功，权限已缓存"
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || break; done 2>/dev/null &
    SUDO_KEEPER_PID=$!
else
    err "密码验证失败"; show_cursor; exit 1
fi

# ═══════════════════════════════
# Step 1: Homebrew + Node.js
# ═══════════════════════════════
CURRENT_STEP=1
CURRENT_LABEL="安装 Homebrew + Node.js..."
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if command -v brew &>/dev/null; then
    log "Homebrew 已安装 — $(brew --version | head -1)"
else
    info "正在安装 Homebrew (可见下载进度)..."
    pre_cmd
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        </dev/null
    post_cmd
    log "Homebrew 安装完成"
fi

# 检测路径
if [[ -f /opt/homebrew/bin/brew ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -f /usr/local/bin/brew ]]; then
    HOMEBREW_PREFIX="/usr/local"
else
    err "无法找到 Homebrew"; show_cursor; exit 1
fi
eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"

# ═════ 写入 .zprofile — 登录 shell 自动加载 Homebrew ═════
if ! grep -q "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
    cat >> "$HOME/.zprofile" << BREWEOF

# Homebrew — added by Claude Tools installer
eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
BREWEOF
    log "eval \"\$(brew shellenv)\" 已写入 ~/.zprofile"
else
    log "Homebrew 环境已存在于 ~/.zprofile"
fi
# 同时也写入 .zshrc (交互 shell 备用)
if ! grep -q "brew shellenv" "$PROFILE" 2>/dev/null; then
    echo "" >> "$PROFILE"
    echo "# Homebrew" >> "$PROFILE"
    echo "eval \"\$(${HOMEBREW_PREFIX}/bin/brew shellenv)\"" >> "$PROFILE"
fi

# Node.js
NEED_NODE=false
if ! command -v node &>/dev/null; then
    NEED_NODE=true
elif [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 18 ]]; then
    NEED_NODE=true
    warn "Node.js 版本过低 ($(node -v))，需要 >= 18"
fi

if $NEED_NODE; then
    info "通过 Homebrew 安装 Node.js (可见下载进度)..."
    pre_cmd; brew install node; post_cmd
    log "Node.js $(node -v) (npm $(npm -v)) 安装完成"
else
    log "Node.js 已安装 — $(node -v)"
fi

# PATH
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
CURRENT_LABEL="安装 Claude Code..."
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if command -v claude &>/dev/null; then
    log "Claude Code 已安装 — $(claude --version 2>/dev/null || echo 'ok')"
else
    TMP_INSTALL="/tmp/claude-install-$$.sh"
    info "正在下载 Claude Code 安装脚本 (可见进度条)..."
    pre_cmd; curl -# -fSL "https://claude.ai/install.sh" -o "$TMP_INSTALL"; post_cmd

    if [[ -s "$TMP_INSTALL" ]]; then
        info "正在执行安装..."
        pre_cmd; bash "$TMP_INSTALL"; post_cmd
        if command -v claude &>/dev/null; then
            log "Claude Code 安装完成"
        else
            warn "官方脚本失败，尝试 Homebrew..."
            pre_cmd; brew install --cask claude-code@latest; post_cmd
            log "Claude Code (brew) 安装完成"
        fi
        rm -f "$TMP_INSTALL"
    else
        warn "下载失败，尝试 Homebrew..."
        pre_cmd; brew install --cask claude-code@latest; post_cmd
        log "Claude Code (brew) 安装完成"
    fi
fi

# ═══════════════════════════════
# Step 3: CC-Switch
# ═══════════════════════════════
CURRENT_STEP=3
CURRENT_LABEL="安装 CC-Switch..."
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if [[ -d "/Applications/CC-Switch.app" ]]; then
    log "CC-Switch 已安装"
else
    info "添加软件源..."
    brew tap farion1231/ccswitch 2>> "$LOG_FILE" || true
    info "下载安装 CC-Switch (可见 brew 下载进度)..."
    pre_cmd; brew install --cask cc-switch; post_cmd
    if [[ -d "/Applications/CC-Switch.app" ]]; then
        log "CC-Switch 安装完成 → /Applications/CC-Switch.app"
    else
        warn "安装失败，手动下载: https://github.com/farion1231/cc-switch/releases"
    fi
fi

# ═══════════════════════════════
# Step 4: CloudCLI
# ═══════════════════════════════
CURRENT_STEP=4
CURRENT_LABEL="安装 CloudCLI (网页版 UI)..."
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
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "安装完成!"
draw_scroll_area

if [[ -n "${SUDO_KEEPER_PID:-}" ]]; then
    kill "$SUDO_KEEPER_PID" 2>/dev/null || true
fi
log "sudo 权限缓存已释放"
hash -r 2>/dev/null || true

# ── 清屏，最终报告 ──
show_cursor
clear_screen

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
echo "  1. 打开 CC-Switch.a添加 API Key"
echo "  2. 或终端输入 claude 进行 OAuth 登录"
echo "  3. 终端输入 cloudcli 启动网页版 UI"
echo ""
echo -e "  ${DIM}安装日志: ${LOG_FILE}${NC}"
echo ""
