#!/usr/bin/env bash
# ============================================================
#  Claude Code 全家桶 — Mac 一键安装脚本
#  包含: Homebrew / Claude Code / CC-Switch / CloudCLI
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

TOTAL_STEPS=6
CURRENT_STEP=0
START_TIME=$(date +%s)
HOMEBREW_PREFIX=""

log()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()   { echo -e "  ${RED}✗${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }

# ── 进度条 ──
progress_bar() {
    local step=$1 total=$2 label="$3"
    local width=30
    local filled=$(( step * width / total ))
    local empty=$(( width - filled ))
    local bar
    bar=$(printf '%*s' "$filled" '' | tr ' ' '═')
    local space
    space=$(printf '%*s' "$empty" '' | tr ' ' '─')
    local pct=$(( step * 100 / total ))
    printf "\n  ${BOLD}${BLUE}[%s%s] %d/%d  %s${NC}\n" "$bar" "$space" "$step" "$total" "$label"
}

# ── 检测 shell 配置文件 ──
detect_shell_profile() {
    case "${SHELL##*/}" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bash_profile" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

# ── 持久化环境变量 ──
persist_env() {
    local var_name="$1" var_value="$2" profile
    profile=$(detect_shell_profile)
    if grep -q "export ${var_name}=" "$profile" 2>/dev/null; then
        # 已存在则替换
        sed -i '' "s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|" "$profile"
    else
        echo "export ${var_name}=\"${var_value}\"" >> "$profile"
    fi
    # 立即生效
    export "${var_name}=${var_value}"
}

# ── 持久化 PATH 追加 ──
persist_path() {
    local dir="$1" profile
    profile=$(detect_shell_profile)
    if [[ ":$PATH:" == *":$dir:"* ]]; then
        return 0
    fi
    if ! grep -F "$dir" "$profile" 2>/dev/null | grep -qv '^#'; then
        echo "export PATH=\"$dir:\$PATH\"" >> "$profile"
    fi
    export PATH="$dir:$PATH"
}

# ── 检查 macOS ──
if [[ "$(uname)" != "Darwin" ]]; then
    err "本脚本仅支持 macOS，当前系统: $(uname)"
    exit 1
fi

clear
echo ""
echo -e "${CYAN}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║     Claude Code 全家桶 — Mac 一键安装            ║${NC}"
echo -e "${CYAN}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  本脚本将安装:"
echo "    • Homebrew      — macOS 包管理器"
echo "    • Node.js       — JavaScript 运行时 (Claude Code 依赖)"
echo "    • Claude Code   — AI 编程助手"
echo "    • CC-Switch     — 模型切换 & MCP 管理"
echo "    • CloudCLI      — 网页版 Claude Code 图形界面"
echo ""
echo -e "  ${YELLOW}安装过程需要写入系统目录，请先输入开机密码。${NC}"
echo ""

# ═══════════════════════════════════════════════════════
# Step 0: 获取 sudo 权限
# ═══════════════════════════════════════════════════════
CURRENT_STEP=$((CURRENT_STEP + 1))
progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "获取系统权限"

if sudo -v; then
    log "密码验证成功，权限已缓存 (有效期 5 分钟)"
    while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || break; done 2>/dev/null &
    SUDO_KEEPER_PID=$!
else
    err "密码验证失败，请重新运行脚本。"
    exit 1
fi

# ═══════════════════════════════════════════════════════
# Step 1: 安装 Homebrew + Node.js + 配置环境变量
# ═══════════════════════════════════════════════════════
CURRENT_STEP=$((CURRENT_STEP + 1))
progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "安装 Homebrew + Node.js"

PROFILE=$(detect_shell_profile)

if command -v brew &>/dev/null; then
    log "Homebrew 已安装"
else
    info "正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
fi

# 检测 Homebrew 路径并持久化
if [[ -f /opt/homebrew/bin/brew ]]; then
    HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -f /usr/local/bin/brew ]]; then
    HOMEBREW_PREFIX="/usr/local"
fi

if [[ -n "$HOMEBREW_PREFIX" ]]; then
    eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
    # 持久化 Homebrew 环境到 shell 配置文件
    if ! grep -q "brew shellenv" "$PROFILE" 2>/dev/null; then
        echo "" >> "$PROFILE"
        echo "# Homebrew" >> "$PROFILE"
        echo "eval \"\$(${HOMEBREW_PREFIX}/bin/brew shellenv)\"" >> "$PROFILE"
        log "Homebrew 环境已写入 ${PROFILE}"
    else
        log "Homebrew 环境已存在于 ${PROFILE}"
    fi
fi

# 安装 Node.js (Claude Code 的运行时依赖)
if command -v node &>/dev/null && [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -ge 18 ]]; then
    log "Node.js 已安装 — $(node -v)"
else
    info "正在安装 Node.js..."
    brew install node && log "Node.js 安装完成 — $(node -v)"
fi

# 持久化 ~/.local/bin 到 PATH
mkdir -p "$HOME/.local/bin"
persist_path "$HOME/.local/bin"
log "~/.local/bin 已加入 PATH"

# ═══════════════════════════════════════════════════════
# Step 2: 安装 Claude Code
# ═══════════════════════════════════════════════════════
CURRENT_STEP=$((CURRENT_STEP + 1))
progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "安装 Claude Code"

if command -v claude &>/dev/null; then
    log "Claude Code 已安装 — $(claude --version 2>/dev/null || echo 'ok')"
else
    info "正在安装 Claude Code (官方脚本)..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        log "Claude Code 安装完成"
    else
        warn "官方脚本失败，通过 Homebrew 安装..."
        brew install --cask claude-code@latest && log "Claude Code 安装完成"
    fi
fi

# 确保安装后 claude 在 PATH 中
if ! command -v claude &>/dev/null && [[ -f "$HOME/.local/bin/claude" ]]; then
    persist_path "$HOME/.local/bin"
fi

# ═══════════════════════════════════════════════════════
# Step 3: 配置 Claude Code 环境变量
# ═══════════════════════════════════════════════════════
CURRENT_STEP=$((CURRENT_STEP + 1))
progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "配置环境变量"

CONFIGURED=0

# 检查有没有现成的 API Key
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    persist_env "ANTHROPIC_API_KEY" "$ANTHROPIC_API_KEY"
    log "ANTHROPIC_API_KEY 已持久化"
    CONFIGURED=1
elif [[ -n "${CLAUDE_API_KEY:-}" ]]; then
    persist_env "CLAUDE_API_KEY" "$CLAUDE_API_KEY"
    log "CLAUDE_API_KEY 已持久化"
    CONFIGURED=1
fi

# 持久化 npm 全局 bin (npx 依赖)
NPM_BIN=""
if command -v npm &>/dev/null; then
    NPM_BIN=$(npm config get prefix 2>/dev/null)/bin
    if [[ -d "$NPM_BIN" ]]; then
        persist_path "$NPM_BIN"
        log "npm 全局 bin 已加入 PATH"
    fi
fi

# 确保 CC-Switch / CloudCLI 相关路径可用
if [[ -f "$HOMEBREW_PREFIX/bin/node" ]]; then
    persist_path "$HOMEBREW_PREFIX/bin"
fi

if [[ "$CONFIGURED" -eq 0 ]]; then
    warn "未检测到 ANTHROPIC_API_KEY，首次运行 claude 时会弹出浏览器登录。"
    warn "你也可以在 CC-Switch 中配置 API Key，或手动设置:"
    echo ""
    echo -e "    ${CYAN}export ANTHROPIC_API_KEY=\"你的key\"${NC}"
    echo ""
fi

# ═══════════════════════════════════════════════════════
# Step 4: 安装 CC-Switch
# ═══════════════════════════════════════════════════════
CURRENT_STEP=$((CURRENT_STEP + 1))
progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "安装 CC-Switch"

if [[ -d "/Applications/CC-Switch.app" ]]; then
    log "CC-Switch 已安装"
else
    info "正在添加软件源 & 安装..."
    brew tap farion1231/ccswitch 2>/dev/null || true
    brew install --cask cc-switch && log "CC-Switch 安装完成 (在 /Applications 中)"
fi

# ═══════════════════════════════════════════════════════
# Step 5: 安装 CloudCLI (Claude Code UI)
# ═══════════════════════════════════════════════════════
CURRENT_STEP=$((CURRENT_STEP + 1))
progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "安装 CloudCLI (网页版 UI)"

CLOUDCLI_BIN="$HOME/.local/bin/cloudcli"
mkdir -p "$HOME/.local/bin"
cat > "$CLOUDCLI_BIN" << 'EOF'
#!/usr/bin/env bash
echo "🚀 正在启动 Claude Code UI..."
echo "   浏览器打开 → http://localhost:3000"
echo "   按 Ctrl+C 停止"
echo ""
npx @cloudcli-ai/cloudcli "$@"
EOF
chmod +x "$CLOUDCLI_BIN"
log "cloudcli 命令已创建: $CLOUDCLI_BIN"

# ═══════════════════════════════════════════════════════
# Step 6: 清理 & 完成
# ═══════════════════════════════════════════════════════
CURRENT_STEP=$((CURRENT_STEP + 1))
progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "清理 & 收尾"

if [[ -n "${SUDO_KEEPER_PID:-}" ]]; then
    kill "$SUDO_KEEPER_PID" 2>/dev/null || true
fi
log "sudo 权限缓存已释放"

# 刷新当前 shell 的环境变量
hash -r 2>/dev/null || true

ELAPSED=$(($(date +%s) - START_TIME))
echo ""
echo -e "${GREEN}  ╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║              安装完成  (耗时 ${ELAPSED}s)             ║${NC}"
echo -e "${GREEN}  ╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}已安装的工具:${NC}"
echo "  ┌──────────────────┬────────────────────────────────────┐"
echo "  │ Claude Code      │ 终端输入 ${BOLD}claude${NC} 启动              │"
echo "  │ CC-Switch        │ 在 /Applications 中打开             │"
echo "  │ Claude Code UI   │ 终端输入 ${BOLD}cloudcli${NC} 启动           │"
echo "  └──────────────────┴────────────────────────────────────┘"
echo ""
echo -e "  ${BOLD}已配置的环境变量:${NC}"
echo "  ┌──────────────────┬────────────────────────────────────┐"
printf "  │ %-16s │ %-34s │\n" "Homebrew" "$PROFILE"
printf "  │ %-16s │ %-34s │\n" "~/.local/bin" "$PROFILE"
if [[ -n "${NPM_BIN:-}" ]]; then
    printf "  │ %-16s │ %-34s │\n" "npm global bin" "$PROFILE"
fi
echo "  └──────────────────┴────────────────────────────────────┘"
echo ""
echo -e "  ${BOLD}下一步:${NC}"
echo "  1. 运行 ${BOLD}source ${PROFILE}${NC} 或重新打开终端，让环境变量生效"
echo "  2. 打开 CC-Switch.app 添加 API Key，或运行 claude 进行登录"
echo "  3. 运行 ${BOLD}cloudcli${NC} 启动网页版图形界面"
echo ""

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "  ${YELLOW}⚠ 当前终端 PATH 还未包含 ~/.local/bin${NC}"
    echo -e "  ${YELLOW}  请运行: source ${PROFILE}${NC}"
    echo ""
fi
