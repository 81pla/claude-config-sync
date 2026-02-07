#!/usr/bin/env bash
# ============================================================
# Claude Code Config Sync - 一键安装脚本
#
# 用法:
#   首台机器（从项目仓库安装）:
#     git clone https://github.com/username/claude-config-sync.git
#     bash claude-config-sync/install.sh
#
#   第二台机器（已有配置仓库）:
#     git clone <config-repo-url> ~/.claude-sync
#     bash ~/.claude-sync/install.sh   （会检测到已有仓库，仅同步配置）
#
#   或直接从项目仓库安装:
#     bash claude-config-sync/install.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_DIR="$HOME/.claude-sync"
CLAUDE_DIR="$HOME/.claude"
SKILL_DIR="$CLAUDE_DIR/skills/config-sync"
MACHINE_ID="$(hostname -s)"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[信息]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[完成]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
log_err()   { echo -e "${RED}[错误]${NC} $*"; }
log_step()  { echo -e "${CYAN}[步骤]${NC} $*"; }

echo ""
echo -e "${BOLD}======================================${NC}"
echo -e "${BOLD}  Claude Code Config Sync - 安装${NC}"
echo -e "  机器: ${CYAN}$MACHINE_ID${NC}"
echo -e "${BOLD}======================================${NC}"
echo ""

# ---- 检测安装模式 ----
# 判断脚本是从项目仓库运行还是从配置仓库运行
IS_PROJECT_REPO=false
IS_CONFIG_REPO=false

if [ -f "$SCRIPT_DIR/skill/SKILL.md" ] && [ -f "$SCRIPT_DIR/sync.sh" ]; then
  IS_PROJECT_REPO=true
  log_info "检测到项目仓库: $SCRIPT_DIR"
fi

if [ "$SCRIPT_DIR" = "$SYNC_DIR" ] && [ -d "$SYNC_DIR/.git" ]; then
  IS_CONFIG_REPO=true
  log_info "检测到配置仓库: $SYNC_DIR"
fi

# ================================================================
# Step 1: 安装 sync.sh 到 ~/.claude-sync/
# ================================================================
log_step "1/4 安装同步脚本"

mkdir -p "$SYNC_DIR"

if [ "$IS_CONFIG_REPO" = true ]; then
  # 从已有的配置仓库安装（第二台机器场景）
  # sync.sh 应该已经在 ~/.claude-sync/ 中了
  if [ -f "$SYNC_DIR/sync.sh" ]; then
    log_ok "sync.sh 已存在于配置仓库中"
  else
    # 配置仓库中没有 sync.sh，从项目仓库复制（如果可用）
    if [ "$IS_PROJECT_REPO" = true ]; then
      cp "$SCRIPT_DIR/sync.sh" "$SYNC_DIR/sync.sh"
      log_ok "sync.sh 已从项目仓库复制"
    else
      log_err "找不到 sync.sh，请确保配置仓库或项目仓库中包含该文件"
      exit 1
    fi
  fi
elif [ "$IS_PROJECT_REPO" = true ]; then
  # 从项目仓库安装（首台机器场景）
  cp "$SCRIPT_DIR/sync.sh" "$SYNC_DIR/sync.sh"
  log_ok "sync.sh 已安装到 $SYNC_DIR/"
else
  log_err "无法确定安装来源，请从项目仓库或配置仓库目录运行此脚本"
  exit 1
fi

chmod +x "$SYNC_DIR/sync.sh"

# ================================================================
# Step 2: 安装 SKILL.md 到 ~/.claude/skills/config-sync/
# ================================================================
log_step "2/4 安装 Skill 定义"

mkdir -p "$SKILL_DIR"

if [ "$IS_PROJECT_REPO" = true ]; then
  cp "$SCRIPT_DIR/skill/SKILL.md" "$SKILL_DIR/SKILL.md"
  log_ok "SKILL.md 已安装到 $SKILL_DIR/"
elif [ -f "$SYNC_DIR/skills/config-sync/SKILL.md" ]; then
  # 从配置仓库的同步数据中恢复
  cp "$SYNC_DIR/skills/config-sync/SKILL.md" "$SKILL_DIR/SKILL.md"
  log_ok "SKILL.md 已从配置仓库恢复"
elif [ -f "$SCRIPT_DIR/skill/SKILL.md" ]; then
  cp "$SCRIPT_DIR/skill/SKILL.md" "$SKILL_DIR/SKILL.md"
  log_ok "SKILL.md 已安装"
else
  log_warn "未找到 SKILL.md，跳过 Skill 安装"
fi

# ================================================================
# Step 3: 初始化或同步配置仓库
# ================================================================
log_step "3/4 配置同步仓库"

if [ -d "$SYNC_DIR/.git" ]; then
  # 配置仓库已存在（第二台机器从 clone 而来）
  log_info "配置仓库已存在，同步配置到本地..."

  # 定义同步项
  SYNC_ITEMS=(
    "CLAUDE.md"
    "settings.json"
    "mcp.json"
    "keybindings.json"
    "agents"
    "skills"
  )

  RSYNC_EXCLUDES=(
    "--exclude=__pycache__"
    "--exclude=*.pyc"
    "--exclude=.DS_Store"
    "--exclude=node_modules"
  )

  # 确保 ~/.claude/ 基础目录存在
  mkdir -p "$CLAUDE_DIR"
  mkdir -p "$CLAUDE_DIR/agents"
  mkdir -p "$CLAUDE_DIR/skills"

  # 将配置仓库中的文件同步到 ~/.claude/
  for item in "${SYNC_ITEMS[@]}"; do
    src="$SYNC_DIR/$item"
    dst="$CLAUDE_DIR/$item"

    [ ! -e "$src" ] && continue

    if [ -d "$src" ]; then
      mkdir -p "$dst"
      rsync -a "${RSYNC_EXCLUDES[@]}" "$src/" "$dst/"
      echo -e "  ${GREEN}+${NC} $item/"
    else
      # 如果本地已有同名文件，备份
      if [ -f "$dst" ]; then
        cp "$dst" "$dst.backup.$(date +%s)"
        echo -e "  ${GREEN}+${NC} $item (已备份原文件)"
      else
        echo -e "  ${GREEN}+${NC} $item"
      fi
      cp "$src" "$dst"
    fi
  done

  log_ok "配置已同步到 ~/.claude/"
else
  # 首台机器：初始化配置仓库
  log_info "首次安装，初始化配置仓库..."

  cd "$SYNC_DIR"
  git init -b main

  # 创建 .gitignore
  cat > "$SYNC_DIR/.gitignore" << 'GITIGNORE'
.DS_Store
__pycache__/
*.pyc
node_modules/
GITIGNORE

  # 将当前 ~/.claude/ 中的配置复制到同步仓库
  SYNC_ITEMS=(
    "CLAUDE.md"
    "settings.json"
    "mcp.json"
    "keybindings.json"
    "agents"
    "skills"
  )

  RSYNC_EXCLUDES=(
    "--exclude=__pycache__"
    "--exclude=*.pyc"
    "--exclude=.DS_Store"
    "--exclude=node_modules"
  )

  mkdir -p "$CLAUDE_DIR"

  for item in "${SYNC_ITEMS[@]}"; do
    src="$CLAUDE_DIR/$item"
    dst="$SYNC_DIR/$item"

    [ ! -e "$src" ] && continue

    if [ -d "$src" ]; then
      mkdir -p "$dst"
      rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$src/" "$dst/"
      echo -e "  ${GREEN}+${NC} $item/"
    else
      cp "$src" "$dst"
      echo -e "  ${GREEN}+${NC} $item"
    fi
  done

  # 初始提交
  cd "$SYNC_DIR"
  git add -A
  git commit -m "init: 初始化配置 [$MACHINE_ID]"

  log_ok "配置仓库已初始化于 $SYNC_DIR"
fi

# ================================================================
# Step 4: 检查依赖环境
# ================================================================
log_step "4/5 检查依赖环境"

if [ -x "$SYNC_DIR/sync.sh" ]; then
  bash "$SYNC_DIR/sync.sh" deps check
fi

# ================================================================
# Step 5: 完成提示
# ================================================================
log_step "5/5 安装完成"

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

if [ -d "$SYNC_DIR/.git" ] && cd "$SYNC_DIR" && git remote get-url origin &>/dev/null 2>&1; then
  # 已有远程仓库
  echo -e "${BOLD}使用方法:${NC}"
  echo "  在 Claude Code 中直接输入以下命令:"
  echo ""
  echo "    /sync          智能双向合并（推荐日常使用）"
  echo "    /sync status   查看同步状态"
  echo "    /sync push     推送本地变更到远程"
  echo "    /sync pull     拉取远程变更到本地"
  echo "    /sync help     查看所有可用命令"
else
  # 还未配置远程
  echo -e "${BOLD}下一步:${NC}"
  echo ""
  echo "  1. 在 GitHub 创建一个 ${BOLD}私有仓库${NC}（用于存储配置）"
  echo "     例如: claude-config"
  echo ""
  echo "  2. 在 Claude Code 中运行:"
  echo "     ${CYAN}/sync remote git@github.com:username/claude-config.git${NC}"
  echo ""
  echo "  3. 在其他机器上:"
  echo "     ${CYAN}git clone git@github.com:username/claude-config.git ~/.claude-sync${NC}"
  echo "     ${CYAN}bash ~/.claude-sync/install.sh${NC}"
  echo ""
  echo -e "${BOLD}日常使用:${NC}"
  echo "  在 Claude Code 中输入 /sync 即可同步配置"
fi

echo ""
