#!/usr/bin/env bash
# ============================================================
#  Claude Code 全家桶 — Mac 一键安装脚本
#  v5: 方框固定头部 + 原生下载进度条 + 错误重试
# ============================================================
set -euo pipefail

# ══ 关键：重新把 stdin 连到终端，否则 brew/curl 会抑制进度条 ══
# 本脚本通常以 bash <(curl ...) 运行，stdin 是管道而非 TTY。
# brew/curl 检测到非 TTY 环境就会关闭交互式进度条。
exec 0</dev/tty

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

START_TIME=$(date +%s)
LOG_FILE="/tmp/claude-tools-install-$$.log"
SCROLL_LINES=()
CURRENT_STEP=0; TOTAL_STEPS=5; CURRENT_LABEL=""
HEADER_LINES=12

# ── 终端控制 ──
term_rows() { tput lines 2>/dev/null || echo 40; }
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

# ── 恢复全终端滚动（长命令前调用）──
release_scroll() {
    tput csr 0 "$(term_rows)" 2>/dev/null || true
    # 光标移到屏幕底部
    printf '\033[%d;0H' "$(term_rows)"
}

# ── 锁定滚动区域（长命令后调用）──
lock_scroll() {
    tput csr "$HEADER_LINES" "$(term_rows)" 2>/dev/null || true
}

# ── 执行需要显示原生进度条的命令 ──
run_cmd() {
    local desc="$1"; shift
    info "${desc}..."
    release_scroll
    # stdin 连到 TTY，brew/curl 原生进度条正常显示
    "$@" </dev/tty
    local rc=$?
    lock_scroll
    return $rc
}

# ── 绘制固定头部方框 ──
draw_header() {
    local step=$1 total=$2 label="$3"
    local elapsed=$(($(date +%s) - START_TIME))
    local TW=46

    release_scroll
    printf '\033[H'

    printf "  ${CYAN}${BOLD}╔%s╗${NC}\n" "$(printf '═%.0s' $(seq 1 $TW))"
    printf "  ${CYAN}${BOLD}║${NC} ${BOLD}Claude Code 全家桶 — Mac 一键安装${NC}%*s${CYAN}${BOLD}║${NC}\n" \
        $((TW - 19 - 1)) ""
    printf "  ${CYAN}╟%s╢${NC}\n" "$(printf '─%.0s' $(seq 1 $TW))"
    printf "  ${CYAN}║${NC} ${DIM}▸ Homebrew  ▸ Node.js  ▸ Claude Code  ▸ CC-Switch  ▸ CloudCLI${NC}%*s${CYAN}║${NC}\n" \
        $((TW - 59)) ""
    printf "  ${CYAN}║${NC}%*s${CYAN}║${NC}\n" "$TW" ""

    local width=30
    local filled=$(( step * width / (total > 0 ? total : 1) ))
    local empty=$(( width - filled ))
    local bar_filled bar_empty pct
    bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '█')
    bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')
    pct=$(( step * 100 / (total > 0 ? total : 1) ))

    printf "  ${CYAN}║${NC} ${BLUE}${BOLD}%s%s${NC} ${BOLD}%3d%%${NC}  ${DIM}%d/%d${NC}" \
        "$bar_filled" "$bar_empty" "$pct" "$step" "$total"
    printf "  ${DIM}%ds${NC}%*s${CYAN}║${NC}\n" "$elapsed" \
        $((TW - 30 - 12 - 10)) ""
    printf "  ${CYAN}║${NC} ${CYAN}→ %s${NC}%*s${CYAN}║${NC}\n" "$label" \
        $((TW - ${#label} - 2)) ""
    printf "  ${CYAN}╚%s╝${NC}\n" "$(printf '═%.0s' $(seq 1 $TW))"

    lock_scroll
}

# ── 滚动日志区 ──
draw_scroll_area() {
    local rows scroll_start max_visible total_logs start_idx i
    rows=$(term_rows)
    scroll_start=$((HEADER_LINES + 1))
    printf '\033[%d;0H' "$scroll_start"
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

# ── Shell 配置 ──
detect_profile() {
    case "${SHELL##*/}" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bash_profile" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}
persist_path() {
    local dir="$1" profile; profile=$(detect_profile)
    [[ ":$PATH:" == *":$dir:"* ]] || export PATH="$dir:$PATH"
    grep -qF "$dir" "$profile" 2>/dev/null || \
        printf '\n# Claude Tools installer\nexport PATH="%s:$PATH"\n' "$dir" >> "$profile"
}

# ═══════════════════════════════════════════
if [[ "$(uname)" != "Darwin" ]]; then
    echo "仅支持 macOS" && exit 1
fi

trap 'release_scroll; show_cursor; exit 1' INT TERM
trap 'release_scroll; show_cursor' EXIT

hide_cursor; printf '\033[2J\033[H'
lock_scroll
draw_header 0 "$TOTAL_STEPS" "初始化..."
draw_scroll_area
PROFILE=$(detect_profile)

# ═══════════════ Step 0: sudo ═══════════════
printf '\n'
printf "  ${YELLOW}${BOLD}🔐 请输入你的 Mac 开机密码，然后按回车:${NC}\n\n"

if sudo -v; then
    log "密码验证成功，权限已缓存（安装期间自动续期）"
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || break; done 2>/dev/null &
    SUDO_KEEPER_PID=$!
else
    err "密码验证失败"; show_cursor; exit 1
fi

# ═══════════════ Step 1: Homebrew + Node.js ═══════════════
CURRENT_STEP=1
CURRENT_LABEL="安装 Homebrew + Node.js + 环境变量"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if command -v brew &>/dev/null; then
    log "Homebrew 已安装 — $(brew --version | head -1)"
else
    info "安装 Homebrew（下方可见 git clone 进度）..."
    release_scroll
    set +e
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL --retry 3 --retry-delay 5 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        </dev/tty 2>&1
    local brew_rc=$?
    set -e
    lock_scroll

    if (( brew_rc == 0 )) && command -v brew &>/dev/null; then
        log "Homebrew 安装完成"
    else
        err "Homebrew 安装失败 (exit=${brew_rc})"
        err "常见原因: 网络不通、DNS 污染。请检查能否访问 github.com"
        err "也可手动安装:"
        err "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        show_cursor; exit 1
    fi
fi

# Homebrew 路径
if [[ -f /opt/homebrew/bin/brew ]]; then HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -f /usr/local/bin/brew ]]; then HOMEBREW_PREFIX="/usr/local"
else err "找不到 Homebrew 路径"; show_cursor; exit 1
fi
eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"

# 写入 ~/.zprofile
if ! grep -q "brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
    cat >> "$HOME/.zprofile" << BREWEOF

# Homebrew
eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
BREWEOF
    log "eval \"\$(brew shellenv)\" → ~/.zprofile"
else
    log "Homebrew 环境已存在 ~/.zprofile"
fi
grep -q "brew shellenv" "$PROFILE" 2>/dev/null || \
    printf '\n# Homebrew\neval "$(%s/bin/brew shellenv)"\n' "$HOMEBREW_PREFIX" >> "$PROFILE"

# Node.js
NEED_NODE=false
if ! command -v node &>/dev/null; then NEED_NODE=true
elif [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 18 ]]; then
    NEED_NODE=true; warn "Node.js $(node -v) 版本过低，需 >= 18"
fi

if $NEED_NODE; then
    if run_cmd "安装 Node.js" brew install node; then
        log "Node.js $(node -v) + npm $(npm -v) 安装完成"
    else
        err "Node.js 安装失败"; show_cursor; exit 1
    fi
else
    log "Node.js 已安装 — $(node -v)"
fi

mkdir -p "$HOME/.local/bin"
persist_path "$HOME/.local/bin"
NPM_BIN=""
if command -v npm &>/dev/null; then
    NPM_BIN=$(npm config get prefix 2>/dev/null)/bin
    [[ -d "$NPM_BIN" && "$NPM_BIN" != "/usr/bin" ]] && persist_path "$NPM_BIN"
fi
log "PATH 已写入 ${PROFILE}"

# ═══════════════ Step 2: Claude Code ═══════════════
CURRENT_STEP=2
CURRENT_LABEL="安装 Claude Code"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if command -v claude &>/dev/null; then
    log "Claude Code 已安装 — $(claude --version 2>/dev/null || echo ok)"
else
    TMP_INSTALL="/tmp/claude-install-$$.sh"

    set +e
    run_cmd "下载 Claude Code 安装脚本" \
        curl -# --retry 3 --retry-delay 5 -fSL \
            "https://claude.ai/install.sh" -o "$TMP_INSTALL"
    local curl_rc=$?
    set -e

    if (( curl_rc != 0 )) || [[ ! -s "$TMP_INSTALL" ]]; then
        warn "官方脚本下载失败，切换 Homebrew cask..."
        if run_cmd "安装 Claude Code (brew)" brew install --cask claude-code@latest; then
            log "Claude Code (brew) 安装完成"
        else
            err "Claude Code 安装失败"; show_cursor; exit 1
        fi
    else
        set +e
        run_cmd "执行 Claude Code 安装脚本" bash "$TMP_INSTALL"
        local install_rc=$?
        set -e
        rm -f "$TMP_INSTALL"
        if (( install_rc == 0 )) && command -v claude &>/dev/null; then
            log "Claude Code 安装完成"
        else
            warn "官方脚本失败，切换 Homebrew cask..."
            run_cmd "安装 Claude Code (brew)" brew install --cask claude-code@latest && \
                log "Claude Code (brew) 安装完成" || \
                { err "Claude Code 安装失败"; show_cursor; exit 1; }
        fi
    fi
fi

# ═══════════════ Step 3: CC-Switch ═══════════════
CURRENT_STEP=3
CURRENT_LABEL="安装 CC-Switch"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

if [[ -d "/Applications/CC-Switch.app" ]]; then
    log "CC-Switch 已安装"
else
    brew tap farion1231/ccswitch 2>> "$LOG_FILE" || true
    if run_cmd "安装 CC-Switch" brew install --cask cc-switch; then
        [[ -d "/Applications/CC-Switch.app" ]] && \
            log "CC-Switch → /Applications/CC-Switch.app" || \
            warn "安装完成但未找到 .app，请检查"
    else
        warn "brew 安装失败，请手动下载:"
        warn "https://github.com/farion1231/cc-switch/releases"
    fi
fi

# ═══════════════ Step 4: CloudCLI ═══════════════
CURRENT_STEP=4
CURRENT_LABEL="安装 CloudCLI (网页版图形界面)"
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
log "cloudcli 命令已创建"

# ═══════════════ Step 5: 完成 ═══════════════
CURRENT_STEP=5
CURRENT_LABEL="全部安装完成!"
draw_header "$CURRENT_STEP" "$TOTAL_STEPS" "$CURRENT_LABEL"
draw_scroll_area

[[ -n "${SUDO_KEEPER_PID:-}" ]] && kill "$SUDO_KEEPER_PID" 2>/dev/null || true
log "sudo 权限已释放"
hash -r 2>/dev/null || true

release_scroll
show_cursor
printf '\033[2J\033[H'

ELAPSED=$(($(date +%s) - START_TIME))
echo ""
echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}  ║          ✅  安装完成!  (耗时 ${ELAPSED}s)              ║${NC}"
echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}已安装的工具:${NC}"
printf "  %-22s → ${BOLD}%s${NC}\n" "Claude Code" "终端输入 claude"
printf "  %-22s → ${BOLD}%s${NC}\n" "CC-Switch" "/Applications/CC-Switch.app"
printf "  %-22s → ${BOLD}%s${NC}\n" "CloudCLI (网页UI)" "终端输入 cloudcli"
echo ""
echo -e "  ${BOLD}环境变量已写入:${NC}"
printf "  %-22s → ${CYAN}%s${NC}\n" "Homebrew shellenv" "~/.zprofile"
printf "  %-22s → ${CYAN}%s${NC}\n" "Homebrew (备用)" "$PROFILE"
printf "  %-22s → ${CYAN}%s${NC}\n" "~/.local/bin PATH" "$PROFILE"
[[ -n "${NPM_BIN:-}" ]] && printf "  %-22s → ${CYAN}%s${NC}\n" "npm global bin" "$PROFILE"
echo ""
echo -e "  ${YELLOW}${BOLD}⚠ 运行此命令使环境变量生效:${NC}"
echo -e "  ${CYAN}source ~/.zprofile && source ${PROFILE}${NC}"
echo ""
echo -e "  ${BOLD}下一步:${NC}"
echo "  1. 打开 CC-Switch.app 添加 API Key"
echo "  2. 或终端输入 claude 进行 OAuth 登录"
echo "  3. 终端输入 cloudcli 启动网页版 UI"
echo ""
echo -e "  ${DIM}日志: ${LOG_FILE}${NC}"
echo ""
