#!/usr/bin/env bash
# ============================================================
#  Claude Code 全家桶 — Mac 一键安装脚本
#  包含: Claude Code / CC-Switch / Claude Code UI (CloudCLI)
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${CYAN}[~]${NC} $1"; }

# ── 检查 macOS ──
if [[ "$(uname)" != "Darwin" ]]; then
    err "本脚本仅支持 macOS，当前系统: $(uname)"
    exit 1
fi

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}   Claude Code 全家桶 — Mac 一键安装${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "  本脚本将安装以下工具:"
echo "    • Homebrew      — macOS 包管理器"
echo "    • Claude Code   — AI 编程助手"
echo "    • CC-Switch     — 模型切换 & MCP 管理"
echo "    • CloudCLI      — 网页版 Claude Code 图形界面"
echo ""
echo -e "  ${YELLOW}安装过程中需要写入 /Applications 等系统目录，${NC}"
echo -e "  ${YELLOW}请在下方输入你的开机密码以授权。${NC}"
echo ""

# ── Step 0: 提前获取 sudo 权限，避免安装中途被打断 ──
echo -e "${YELLOW}── Step 0/5: 获取系统权限 ──${NC}"
if sudo -v; then
    log "密码验证成功，权限已缓存"
    # 后台持续刷新 sudo 时间戳，防止长时间安装时权限过期
    while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || break; done 2>/dev/null &
    SUDO_KEEPER_PID=$!
else
    err "密码验证失败，无法继续。请重新运行脚本。"
    exit 1
fi
echo ""

# ── Step 1: 安装 Homebrew ──
echo -e "${YELLOW}── Step 1/5: 检查 Homebrew ──${NC}"
if command -v brew &>/dev/null; then
    log "Homebrew 已安装 — $(brew --version | head -1)"
else
    info "正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # 自动加到 PATH (Apple Silicon)
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    log "Homebrew 安装完成"
fi
echo ""

# ── Step 2: 安装 Claude Code ──
echo -e "${YELLOW}── Step 2/5: 安装 Claude Code ──${NC}"
if command -v claude &>/dev/null; then
    log "Claude Code 已安装 — v$(claude --version 2>/dev/null || echo '?')"
else
    info "正在安装 Claude Code..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        log "Claude Code 安装完成"
    else
        warn "官方脚本失败，尝试 Homebrew 安装..."
        brew install --cask claude-code@latest && log "Claude Code (brew) 安装完成"
    fi
fi

# 确保 ~/.local/bin 在 PATH 中
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    case "${SHELL##*/}" in
        zsh)  PROFILE="$HOME/.zshrc" ;;
        bash) PROFILE="$HOME/.bash_profile" ;;
        *)    PROFILE="$HOME/.profile" ;;
    esac
    if ! grep -q '.local/bin' "$PROFILE" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE"
        info "已将 ~/.local/bin 添加到 $PROFILE"
    fi
fi
echo ""

# ── Step 3: 安装 CC-Switch ──
echo -e "${YELLOW}── Step 3/5: 安装 CC-Switch ──${NC}"
if [[ -d "/Applications/CC-Switch.app" ]]; then
    log "CC-Switch 已安装"
else
    info "正在添加 CC-Switch 软件源..."
    brew tap farion1231/ccswitch 2>/dev/null || true
    info "正在安装 CC-Switch..."
    brew install --cask cc-switch && log "CC-Switch 安装完成"
fi
echo ""

# ── Step 4: 安装 Claude Code UI (CloudCLI) ──
echo -e "${YELLOW}── Step 4/5: 安装 Claude Code UI (CloudCLI) ──${NC}"
info "通过 npx 运行 CloudCLI（首次会自动下载）..."

# 创建快捷启动脚本
LAUNCHER="$HOME/.local/bin/cloudcli"
mkdir -p "$HOME/.local/bin"
cat > "$LAUNCHER" << 'LAUNCHEREOF'
#!/usr/bin/env bash
echo "正在启动 Claude Code UI..."
echo "浏览器打开 http://localhost:3000 即可使用"
npx @cloudcli-ai/cloudcli "$@"
LAUNCHEREOF
chmod +x "$LAUNCHER"
log "CloudCLI 启动脚本已创建: $LAUNCHER"
echo ""

# ── Step 5: 清理 ──
echo -e "${YELLOW}── Step 5/5: 清理 ──${NC}"
if [[ -n "${SUDO_KEEPER_PID:-}" ]]; then
    kill "$SUDO_KEEPER_PID" 2>/dev/null || true
fi
log "sudo 权限缓存已释放"
echo ""

# ── 完成 ──
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   安装完成！${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "  已安装的工具:"
echo "  ┌──────────────────┬────────────────────────────────────┐"
echo "  │ Claude Code      │ 终端输入 claude 启动               │"
echo "  │ CC-Switch        │ 在 /Applications 中打开            │"
echo "  │ Claude Code UI   │ 终端输入 cloudcli 启动              │"
echo "  └──────────────────┴────────────────────────────────────┘"
echo ""
echo -e "  ${YELLOW}下一步:${NC}"
echo "  1. 打开 CC-Switch.app，添加 API Key（Claude / OpenAI / Gemini）"
echo "  2. 或在终端输入 claude 进行首次登录认证"
echo "  3. 输入 cloudcli 启动网页版图形界面"
echo ""

# 检查是否需要重新加载 shell
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "  ${YELLOW}提示: 运行以下命令使 PATH 生效:${NC}"
    echo "  source ~/.zshrc"
    echo ""
fi
