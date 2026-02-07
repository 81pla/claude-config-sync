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

# 插件元数据（只同步清单，不同步插件本体）
PLUGIN_META_FILES=(
  "plugins/known_marketplaces.json"
  "plugins/installed_plugins.json"
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

  # 插件元数据
  for file in "${PLUGIN_META_FILES[@]}"; do
    local src="$CLAUDE_DIR/$file"
    local dst="$SYNC_DIR/$file"
    if [ -f "$src" ]; then
      mkdir -p "$(dirname "$dst")"
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

  # 插件元数据
  for file in "${PLUGIN_META_FILES[@]}"; do
    local src="$SYNC_DIR/$file"
    local dst="$CLAUDE_DIR/$file"
    if [ -f "$src" ]; then
      mkdir -p "$(dirname "$dst")"
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

# ================================================================
# 依赖检测与安装
# ================================================================

# 从 mcp.json 和 settings.json 提取 npx 包名
extract_mcp_packages() {
  python3 -c "
import json, os
seen = set()
for f in ['$CLAUDE_DIR/mcp.json', '$CLAUDE_DIR/settings.json']:
    if not os.path.isfile(f): continue
    try:
        with open(f) as fh:
            data = json.load(fh)
        servers = data.get('mcpServers', {})
        for name, cfg in servers.items():
            cmd = cfg.get('command', '')
            if cmd == 'npx':
                args = cfg.get('args', [])
                for a in args:
                    if not a.startswith('-'):
                        if a not in seen:
                            seen.add(a)
                            print(a)
                        break
    except: pass
" 2>/dev/null
}

# 从 known_marketplaces.json 提取插件信息
extract_plugins() {
  local meta="$CLAUDE_DIR/plugins/known_marketplaces.json"
  [ ! -f "$meta" ] && return
  python3 -c "
import json
try:
    with open('$meta') as f:
        data = json.load(f)
    for name, info in data.items():
        repo = info.get('source', {}).get('repo', '')
        if repo:
            print(f'{name}|{repo}')
except: pass
" 2>/dev/null
}

cmd_deps() {
  local mode="${1:-check}"   # check | install
  local missing=0
  local ok_count=0

  echo ""
  echo -e "${BOLD}══════════════════════════════════════${NC}"
  echo -e "${BOLD}  依赖环境检查${NC}"
  echo -e "  机器: ${CYAN}$MACHINE_ID${NC}"
  echo -e "${BOLD}══════════════════════════════════════${NC}"
  echo ""

  # ---- 1. 系统工具 ----
  echo -e "${BOLD}── 系统工具 ──${NC}"

  local tools_to_install=()

  check_tool() {
    local tool="$1"
    local install_hint="$2"
    if command -v "$tool" &>/dev/null; then
      local ver
      ver=$("$tool" --version 2>/dev/null | head -1)
      echo -e "  ${GREEN}✓${NC} $tool  ($ver)"
      ok_count=$((ok_count + 1))
    else
      echo -e "  ${RED}✗${NC} $tool  — 安装: $install_hint"
      tools_to_install+=("$tool")
      missing=$((missing + 1))
    fi
  }

  check_tool node "brew install node"
  check_tool npx  "brew install node"
  check_tool git  "xcode-select --install"
  check_tool python3 "xcode-select --install"
  check_tool rsync "brew install rsync"

  # bun（可能在 ~/.bun/bin/ 下）
  if command -v bun &>/dev/null; then
    local ver
    ver=$(bun --version 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} bun  ($ver)"
    ok_count=$((ok_count + 1))
  elif [ -x "$HOME/.bun/bin/bun" ]; then
    local ver
    ver=$("$HOME/.bun/bin/bun" --version 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} bun  ($ver) [~/.bun/bin/bun]"
    ok_count=$((ok_count + 1))
  else
    echo -e "  ${RED}✗${NC} bun  — 安装: curl -fsSL https://bun.sh/install | bash"
    tools_to_install+=("bun")
    missing=$((missing + 1))
  fi

  # claude CLI
  if command -v claude &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} claude CLI"
    ok_count=$((ok_count + 1))
  else
    echo -e "  ${RED}✗${NC} claude CLI  — 安装: npm install -g @anthropic-ai/claude-code"
    tools_to_install+=("claude")
    missing=$((missing + 1))
  fi

  # ---- 2. MCP 服务器 ----
  echo ""
  echo -e "${BOLD}── MCP 服务器 ──${NC}"

  local mcp_packages=()
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && mcp_packages+=("$pkg")
  done < <(extract_mcp_packages)

  if [ ${#mcp_packages[@]} -eq 0 ]; then
    echo "  (无 MCP 依赖)"
  else
    for pkg in "${mcp_packages[@]}"; do
      # 检查 npm 全局缓存或 npx 缓存
      if npm list -g "$pkg" &>/dev/null 2>&1 || \
         [ -d "$HOME/.npm/_npx" ] && find "$HOME/.npm/_npx" -path "*/$pkg" -type d 2>/dev/null | grep -q .; then
        echo -e "  ${GREEN}✓${NC} $pkg"
        ((ok_count++)) || true
      else
        echo -e "  ${YELLOW}○${NC} $pkg  (npx -y 首次使用时自动安装)"
      fi
    done
  fi

  # ---- 3. 插件 ----
  echo ""
  echo -e "${BOLD}── 插件 ──${NC}"

  local plugins_to_install=()
  local has_plugins=false

  while IFS='|' read -r name repo; do
    [ -z "$name" ] && continue
    has_plugins=true
    if [ -d "$CLAUDE_DIR/plugins/cache/$name" ]; then
      echo -e "  ${GREEN}✓${NC} $name  (from $repo)"
      ((ok_count++)) || true
    else
      echo -e "  ${RED}✗${NC} $name  — 安装: claude plugin add $repo"
      plugins_to_install+=("$name|$repo")
      ((missing++)) || true
    fi
  done < <(extract_plugins)

  $has_plugins || echo "  (无插件)"

  # ---- 4. 自定义依赖 ----
  if [ -f "$SYNC_DIR/postinstall.sh" ]; then
    echo ""
    echo -e "${BOLD}── 自定义脚本 ──${NC}"
    echo "  postinstall.sh 存在"
  fi

  # ---- 汇总 ----
  echo ""
  echo "────────────────────────────────────"
  if [ "$missing" -gt 0 ]; then
    echo -e "  ${GREEN}$ok_count 项就绪${NC} / ${RED}$missing 项缺失${NC}"
    if [ "$mode" = "check" ]; then
      echo ""
      echo -e "  运行 ${BOLD}/sync deps install${NC} 自动安装缺失项"
    fi
  else
    echo -e "  ${GREEN}全部 $ok_count 项就绪！${NC}"
  fi
  echo ""

  # ---- 自动安装模式 ----
  if [ "$mode" = "install" ] && [ "$missing" -gt 0 ]; then
    echo -e "${BOLD}开始安装缺失依赖...${NC}"
    echo ""

    # 系统工具
    for tool in "${tools_to_install[@]}"; do
      case "$tool" in
        node|npx)
          log_step "安装 Node.js..."
          if command -v brew &>/dev/null; then
            brew install node 2>&1 | tail -3
            log_ok "Node.js 已安装"
          else
            log_warn "未找到 Homebrew，请手动安装: brew install node"
          fi
          ;;
        bun)
          log_step "安装 Bun..."
          curl -fsSL https://bun.sh/install | bash 2>&1 | tail -3
          log_ok "Bun 已安装"
          ;;
        claude)
          log_step "安装 Claude CLI..."
          if command -v npm &>/dev/null; then
            npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
            log_ok "Claude CLI 已安装"
          else
            log_warn "需要先安装 Node.js"
          fi
          ;;
        git|python3|rsync)
          log_step "安装 $tool..."
          if command -v brew &>/dev/null; then
            brew install "$tool" 2>&1 | tail -3
            log_ok "$tool 已安装"
          else
            log_warn "请手动安装 $tool"
          fi
          ;;
      esac
    done

    # 插件
    for entry in "${plugins_to_install[@]}"; do
      local name="${entry%%|*}"
      local repo="${entry#*|}"
      log_step "安装插件 $name..."
      if command -v claude &>/dev/null; then
        claude plugin add "$repo" 2>&1 | tail -5
        log_ok "插件 $name 已安装"
      else
        log_warn "Claude CLI 不可用，请手动安装: claude plugin add $repo"
      fi
    done

    # 自定义脚本
    if [ -f "$SYNC_DIR/postinstall.sh" ]; then
      log_step "运行自定义安装脚本..."
      bash "$SYNC_DIR/postinstall.sh"
      log_ok "自定义脚本执行完成"
    fi

    echo ""
    log_ok "依赖安装完成！"
    echo ""
  fi
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

  依赖管理:
    /sync deps              检查依赖环境
    /sync deps install      自动安装缺失依赖

  冲突处理:
    /sync resolve           解决冲突后完成同步

  ──────────────────────────────────────
  同步范围:
    CLAUDE.md, settings.json, mcp.json,
    keybindings.json, agents/, skills/,
    plugins 元数据 (清单，非插件本体)

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
  deps)    cmd_deps "${2:-check}" ;;
  help|-h|--help) cmd_help ;;
  *)
    log_err "未知命令: $1"
    echo "运行 /sync help 查看帮助"
    exit 1
    ;;
esac
