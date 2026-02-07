#!/usr/bin/env bash
# ============================================================
# Claude Code Config Sync
# 通过 Git 在不同机器间智能同步 Claude Code 配置
# ============================================================

set -euo pipefail

SYNC_DIR="${CLAUDE_SYNC_DIR:-$HOME/.claude-sync}"
CLAUDE_DIR="$HOME/.claude"
MACHINE_ID="$(hostname -s)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- 同步范围 ----
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

# ---- 工具函数 ----
log_info()  { echo -e "${BLUE}[信息]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[完成]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
log_err()   { echo -e "${RED}[错误]${NC} $*"; }
log_step()  { echo -e "${CYAN}[步骤]${NC} $*"; }

ensure_repo() {
  if [ ! -d "$SYNC_DIR/.git" ]; then
    log_err "同步仓库不存在，请先运行: /sync init"
    exit 1
  fi
}

current_branch() {
  cd "$SYNC_DIR"
  git branch --show-current 2>/dev/null || echo "main"
}

has_remote() {
  cd "$SYNC_DIR"
  git remote get-url origin &>/dev/null
}

repo_has_changes() {
  cd "$SYNC_DIR"
  ! git diff --quiet 2>/dev/null || \
  ! git diff --cached --quiet 2>/dev/null || \
  [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]
}

# 将 ~/.claude/ 的配置复制到同步仓库
copy_local_to_repo() {
  for item in "${SYNC_ITEMS[@]}"; do
    local src="$CLAUDE_DIR/$item"
    local dst="$SYNC_DIR/$item"

    [ ! -e "$src" ] && continue

    if [ -d "$src" ]; then
      mkdir -p "$dst"
      rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$src/" "$dst/"
    else
      cp "$src" "$dst"
    fi
  done
}

# 将同步仓库的配置复制回 ~/.claude/
copy_repo_to_local() {
  for item in "${SYNC_ITEMS[@]}"; do
    local src="$SYNC_DIR/$item"
    local dst="$CLAUDE_DIR/$item"

    [ ! -e "$src" ] && continue

    if [ -d "$src" ]; then
      mkdir -p "$dst"
      rsync -a "${RSYNC_EXCLUDES[@]}" "$src/" "$dst/"
    else
      cp "$src" "$dst"
    fi
  done
}

# 生成变更摘要（不修改仓库）
diff_local_vs_repo() {
  local changed=()
  local added=()
  local removed=()

  for item in "${SYNC_ITEMS[@]}"; do
    local src="$CLAUDE_DIR/$item"
    local dst="$SYNC_DIR/$item"

    if [ ! -e "$src" ] && [ ! -e "$dst" ]; then
      continue
    elif [ ! -e "$dst" ]; then
      added+=("$item")
    elif [ ! -e "$src" ]; then
      removed+=("$item")
    elif [ -d "$src" ]; then
      local dir_diff
      dir_diff=$(diff -rq "$src" "$dst" \
        --exclude="__pycache__" --exclude=".DS_Store" \
        --exclude="*.pyc" --exclude="node_modules" 2>/dev/null || true)
      [ -n "$dir_diff" ] && changed+=("$item")
    else
      diff -q "$src" "$dst" &>/dev/null || changed+=("$item")
    fi
  done

  # 输出
  local has_diff=false
  for f in "${added[@]+"${added[@]}"}"; do
    echo -e "  ${GREEN}+ [新增]${NC} $f"
    has_diff=true
  done
  for f in "${changed[@]+"${changed[@]}"}"; do
    echo -e "  ${YELLOW}~ [修改]${NC} $f"
    has_diff=true
  done
  for f in "${removed[@]+"${removed[@]}"}"; do
    echo -e "  ${RED}- [删除]${NC} $f"
    has_diff=true
  done

  $has_diff || echo "  (无差异)"
}

# ================================================================
# 命令实现
# ================================================================

cmd_init() {
  if [ -d "$SYNC_DIR/.git" ]; then
    log_warn "同步仓库已存在于 $SYNC_DIR"
    return 0
  fi

  cd "$SYNC_DIR"
  git init -b main

  cat > .gitignore << 'EOF'
.DS_Store
__pycache__/
*.pyc
node_modules/
EOF

  copy_local_to_repo
  git add -A
  git commit -m "init: 初始化配置 [$MACHINE_ID]"

  echo ""
  log_ok "同步仓库已创建于 $SYNC_DIR"
  echo ""
  echo -e "${BOLD}下一步:${NC}"
  echo "  1. 在 GitHub 创建一个 ${BOLD}私有仓库${NC}"
  echo "  2. 运行: /sync remote <仓库地址>"
  echo ""
  echo "  例如: /sync remote git@github.com:username/claude-config.git"
}

cmd_remote() {
  ensure_repo
  local url="${1:?请提供 Git 远程仓库地址}"
  cd "$SYNC_DIR"

  if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$url"
    log_info "已更新远程地址"
  else
    git remote add origin "$url"
    log_info "已添加远程地址"
  fi

  local branch
  branch=$(current_branch)

  if git push -u origin "$branch" 2>&1; then
    log_ok "远程仓库配置完成: $url"
    echo ""
    echo -e "${BOLD}另一台机器的设置方法:${NC}"
    echo "  git clone $url ~/.claude-sync"
    echo "  bash ~/.claude-sync/install.sh"
  else
    log_err "推送失败，请检查仓库地址和权限"
    return 1
  fi
}

cmd_status() {
  ensure_repo
  cd "$SYNC_DIR"

  echo ""
  echo -e "${BOLD}══════════════════════════════════════${NC}"
  echo -e "${BOLD}  Claude Code 配置同步状态${NC}"
  echo -e "  机器: ${CYAN}$MACHINE_ID${NC}"
  echo -e "${BOLD}══════════════════════════════════════${NC}"
  echo ""

  echo -e "${BOLD}── 本地 vs 仓库 ──${NC}"
  diff_local_vs_repo

  if has_remote; then
    echo ""
    echo -e "${BOLD}── 远程状态 ──${NC}"
    git fetch origin 2>/dev/null || true
    local branch behind ahead
    branch=$(current_branch)
    behind=$(git rev-list --count HEAD..origin/"$branch" 2>/dev/null || echo "?")
    ahead=$(git rev-list --count origin/"$branch"..HEAD 2>/dev/null || echo "?")
    echo "  本地领先: $ahead 个提交"
    echo "  本地落后: $behind 个提交"

    if [ "$behind" != "0" ] && [ "$behind" != "?" ]; then
      echo ""
      echo -e "  ${YELLOW}提示: 远程有新变更，建议运行 /sync 进行同步${NC}"
    fi
  else
    echo ""
    echo -e "  ${YELLOW}远程未配置。运行 /sync remote <url>${NC}"
  fi
  echo ""
}

cmd_diff() {
  ensure_repo
  cd "$SYNC_DIR"

  echo -e "${BOLD}── 本地配置 vs 上次同步 ──${NC}"
  echo ""

  local has_any_diff=false
  for item in "${SYNC_ITEMS[@]}"; do
    local src="$CLAUDE_DIR/$item"
    local dst="$SYNC_DIR/$item"

    [ ! -e "$src" ] && [ ! -e "$dst" ] && continue

    if [ -d "$src" ] && [ -d "$dst" ]; then
      local dir_diff
      dir_diff=$(diff -ru "$dst" "$src" \
        --exclude="__pycache__" --exclude=".DS_Store" \
        --exclude="*.pyc" --exclude="node_modules" 2>/dev/null || true)
      if [ -n "$dir_diff" ]; then
        echo -e "${BOLD}$item/:${NC}"
        echo "$dir_diff"
        echo ""
        has_any_diff=true
      fi
    elif [ -f "$src" ] && [ -f "$dst" ]; then
      local file_diff
      file_diff=$(diff -u "$dst" "$src" 2>/dev/null || true)
      if [ -n "$file_diff" ]; then
        echo -e "${BOLD}$item:${NC}"
        echo "$file_diff"
        echo ""
        has_any_diff=true
      fi
    elif [ -e "$src" ] && [ ! -e "$dst" ]; then
      echo -e "${GREEN}[新增] $item${NC}"
      has_any_diff=true
    elif [ ! -e "$src" ] && [ -e "$dst" ]; then
      echo -e "${RED}[已删] $item${NC}"
      has_any_diff=true
    fi
  done

  $has_any_diff || echo "(无差异)"
}

cmd_sync() {
  ensure_repo
  cd "$SYNC_DIR"

  echo ""
  echo -e "${BOLD}开始同步${NC} (机器: ${CYAN}$MACHINE_ID${NC})"
  echo ""

  # Step 1: 本地 → 仓库
  log_step "1/4 收集本地配置变更"
  copy_local_to_repo

  # Step 2: 提交
  log_step "2/4 提交本地变更"
  if repo_has_changes; then
    git add -A
    local summary
    summary=$(git diff --cached --stat | tail -1)
    git commit -m "sync: [$MACHINE_ID] $TIMESTAMP" --quiet
    log_ok "已提交 ($summary)"
  else
    log_ok "无本地变更"
  fi

  # Step 3: 拉取 + 合并
  log_step "3/4 合并远程变更"
  if has_remote; then
    local branch
    branch=$(current_branch)
    git fetch origin "$branch" 2>/dev/null || true

    local behind
    behind=$(git rev-list --count HEAD..origin/"$branch" 2>/dev/null || echo 0)

    if [ "$behind" -gt 0 ]; then
      local merge_output
      if merge_output=$(git merge origin/"$branch" \
        -m "merge: 合并远程变更 [$MACHINE_ID] $TIMESTAMP" 2>&1); then
        log_ok "已合并远程 $behind 个提交"
      else
        if echo "$merge_output" | grep -q "CONFLICT"; then
          echo ""
          log_err "合并冲突！"
          echo "$merge_output" | grep "CONFLICT" | while read -r line; do
            echo -e "  ${RED}$line${NC}"
          done
          echo ""
          echo -e "${BOLD}解决步骤:${NC}"
          echo "  1. 查看冲突文件:  ls $SYNC_DIR/"
          echo "  2. 手动编辑解决冲突标记 (<<<<<<<, =======, >>>>>>>)"
          echo "  3. 运行: /sync resolve"
          return 1
        fi
        log_err "合并失败: $merge_output"
        return 1
      fi
    else
      log_ok "远程无新变更"
    fi

    # Step 4: 推送
    log_step "4/4 推送合并结果"
    if git push origin "$branch" --quiet 2>&1; then
      log_ok "已推送到远程"
    else
      log_warn "推送失败（可能是网络问题），本地合并已完成"
    fi
  else
    log_warn "未配置远程仓库，跳过远程同步"
    echo "  运行 /sync remote <url> 来配置"
  fi

  # 应用结果到 ~/.claude/
  copy_repo_to_local

  echo ""
  log_ok "同步完成！"
  echo ""
}

cmd_push() {
  ensure_repo
  cd "$SYNC_DIR"

  copy_local_to_repo

  if repo_has_changes; then
    git add -A
    git commit -m "push: [$MACHINE_ID] $TIMESTAMP" --quiet
    log_ok "本地变更已提交"
  else
    log_info "无新变更"
  fi

  if has_remote; then
    local branch
    branch=$(current_branch)
    git push origin "$branch" --quiet
    log_ok "已推送到远程"
  else
    log_warn "未配置远程仓库"
  fi
}

cmd_pull() {
  ensure_repo
  cd "$SYNC_DIR"

  if has_remote; then
    local branch
    branch=$(current_branch)

    # 先保存本地未提交的变更
    copy_local_to_repo
    if repo_has_changes; then
      git stash --quiet
      log_info "已暂存本地变更"
    fi

    git pull origin "$branch" --quiet 2>&1
    log_ok "已拉取远程变更"

    # 恢复本地变更
    if git stash list | grep -q "stash@{0}"; then
      if git stash pop --quiet 2>&1; then
        log_ok "本地变更已恢复"
      else
        log_warn "恢复本地变更时有冲突，运行 /sync resolve 来解决"
        return 1
      fi
    fi
  else
    log_warn "未配置远程仓库"
  fi

  copy_repo_to_local
  log_ok "配置已更新到 ~/.claude/"
}

cmd_resolve() {
  ensure_repo
  cd "$SYNC_DIR"

  local conflicts
  conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null || true)

  if [ -n "$conflicts" ]; then
    log_err "仍有未解决的冲突:"
    echo "$conflicts" | while read -r f; do
      echo -e "  ${RED}$f${NC}"
    done
    echo ""
    echo "请先编辑这些文件，解决冲突标记 (<<<<<<<, =======, >>>>>>>)"
    return 1
  fi

  git add -A
  git commit -m "resolve: 解决冲突 [$MACHINE_ID] $TIMESTAMP" --quiet

  if has_remote; then
    local branch
    branch=$(current_branch)
    git push origin "$branch" --quiet
  fi

  copy_repo_to_local
  log_ok "冲突已解决，同步完成"
}

cmd_log() {
  ensure_repo
  cd "$SYNC_DIR"

  echo -e "${BOLD}── 同步历史 ──${NC}"
  echo ""
  git log --oneline --graph --decorate -20
}

cmd_help() {
  cat << 'EOF'

  ╔══════════════════════════════════════╗
  ║   Claude Code Config Sync           ║
  ║   跨机器配置同步工具                ║
  ╚══════════════════════════════════════╝

  首次设置:
    /sync init              初始化同步仓库
    /sync remote <url>      设置 GitHub 私有仓库地址

  日常使用:
    /sync                   智能双向合并（推荐）
    /sync push              推送本地 → 远程
    /sync pull              拉取远程 → 本地

  查看状态:
    /sync status            同步状态概览
    /sync diff              具体文件差异
    /sync log               同步历史记录

  冲突处理:
    /sync resolve           解决冲突后完成同步

  ──────────────────────────────────────
  同步范围:
    CLAUDE.md, settings.json, mcp.json,
    keybindings.json, agents/, skills/

  不同步 (机器特有):
    settings.local.json, history, cache,
    debug, telemetry, todos, session-env

EOF
}

# ================================================================
# 主入口
# ================================================================
case "${1:-help}" in
  init)    cmd_init ;;
  remote)  cmd_remote "${2:-}" ;;
  sync)    cmd_sync ;;
  push)    cmd_push ;;
  pull)    cmd_pull ;;
  status)  cmd_status ;;
  diff)    cmd_diff ;;
  log)     cmd_log ;;
  resolve) cmd_resolve ;;
  help|-h|--help) cmd_help ;;
  *)
    log_err "未知命令: $1"
    echo "运行 /sync help 查看帮助"
    exit 1
    ;;
esac
