# Claude Code Config Sync

通过 Git 在不同机器间同步 Claude Code 的配置、插件、MCP 服务器和依赖环境。

这是一个 [Claude Code Skill](https://docs.anthropic.com/en/docs/claude-code/skills) 插件，安装后在 Claude Code 中使用 `/sync` 命令即可完成所有同步操作。

## 解决什么问题

Claude Code 没有官方的配置同步功能。当你在多台电脑上使用 Claude Code 时，需要手动在每台机器上重复配置 CLAUDE.md、MCP 服务器、自定义 Agent、Skills、插件等。

本工具让你只需配置一次，之后在任意机器上运行 `/sync` 就能保持一致。

## 功能特性

- **双向智能合并** -- 基于 Git 三路合并，两台机器各自改了不同内容会自动合并
- **动态依赖检测** -- 自动从配置文件中扫描所有引用的命令、MCP 包、插件，无硬编码清单
- **AI 驱动安装** -- 脚本负责诊断环境，Claude AI 负责判断和执行安装
- **同步后自动检查** -- `/sync` 和 `/sync pull` 完成后自动检查依赖是否齐全
- **冲突引导** -- 遇到合并冲突时给出明确的解决步骤
- **Skill 集成** -- 作为 Claude Code Skill 运行，所有操作在对话中完成

## 快速开始

### 首台机器

```bash
# 1. 克隆本项目
git clone https://github.com/81pla/claude-config-sync.git

# 2. 一键安装
bash claude-config-sync/install.sh

# 3. 在 Claude Code 中连接你的私有配置仓库
/sync remote git@github.com:<你的用户名>/claude-config.git
```

### 第二台机器

```bash
# 1. 克隆配置仓库（不是本项目）
git clone git@github.com:<你的用户名>/claude-config.git ~/.claude-sync

# 2. 一键安装（配置 + 依赖检查）
bash ~/.claude-sync/install.sh

# 3. 在 Claude Code 中安装缺失的依赖
/sync deps install
```

> 第二台机器克隆的是你的**配置仓库**（私有），不是这个项目仓库。

## 使用方法

所有操作在 Claude Code 对话中完成：

### 日常使用

```
/sync                智能双向合并（推荐）
/sync push           仅推送本地 → 远程
/sync pull           仅拉取远程 → 本地
```

### 查看状态

```
/sync status         同步状态概览
/sync diff           文件级差异对比
/sync log            同步历史记录
```

### 依赖管理

```
/sync deps           扫描并检查依赖环境
/sync deps install   自动安装缺失依赖
```

### 冲突处理

```
/sync resolve        解决冲突后完成合并
```

### 首次设置

```
/sync init           初始化同步仓库
/sync remote <url>   设置远程仓库地址
/sync help           查看所有命令
```

## 同步范围

### 会同步

| 文件/目录 | 说明 |
|-----------|------|
| `CLAUDE.md` | 全局自定义指令 |
| `settings.json` | Claude Code 设置 |
| `mcp.json` | MCP 服务器配置 |
| `keybindings.json` | 快捷键绑定 |
| `agents/` | 自定义 Agent 定义 |
| `skills/` | Skill 插件（包括本插件自身） |
| `plugins/*.json` | 插件元数据（清单，非插件本体） |

### 不会同步（机器特有）

| 文件/目录 | 原因 |
|-----------|------|
| `settings.local.json` | 包含本地权限规则、密码等敏感信息 |
| `history.jsonl` | 会话历史 |
| `cache/` `debug/` `telemetry/` | 临时/日志数据 |
| `session-env/` `todos/` `plans/` | 会话级状态 |

## 合并策略

`/sync` 使用 Git 三路合并：

```
 本机 ~/.claude/
      │
      ▼  复制到仓库
 ~/.claude-sync/  ──  git commit
      │
      ▼  git pull + merge
 合并远程变更  ──────  git push
      │
      ▼  复制回去
 本机 ~/.claude/  （已合并）
```

- **不同文件各自改了** → 自动合并
- **同一文件不同位置** → 自动合并
- **同一文件同一行** → 报冲突，`/sync resolve` 引导解决

## 依赖管理

同步配置文件只是第一步。新机器上还需要安装配置引用的 MCP 服务器、插件、运行时等。

### 工作原理

`/sync deps` 动态扫描所有配置文件，自动发现依赖：

| 扫描来源 | 提取内容 | 示例 |
|----------|----------|------|
| `mcp.json` / `settings.json` | MCP 服务器引用的命令和包 | `npx` → `@brave/brave-search-mcp-server` |
| `mcp.json` / `settings.json` | 任意命令类型 | `uvx`, `deno`, `python`, 自定义二进制 |
| `settings.json` | statusLine 引用的命令 | `bun` |
| `plugins/known_marketplaces.json` | 插件清单 | `claude-hud` → `jarrodwatts/claude-hud` |
| `skills/*/requirements.txt` | Skill 的 Python 依赖 | `pip install -r requirements.txt` |
| `skills/*/package.json` | Skill 的 npm 依赖 | `npm install` |

**没有硬编码的工具清单**——你以后加任何新 MCP 服务器、新插件、新 Skill，`/sync deps` 都会自动发现。

### 脚本 + AI 协作

```
脚本（sync.sh）        Claude AI
    │                     │
    ├─ 扫描配置文件        │
    ├─ 检查命令是否存在    │
    ├─ 输出诊断报告  ────→ 分析报告
    │                     ├─ 判断安装方法
    │                     ├─ 执行安装命令
    │                     └─ 处理安装失败
    └─ 重新扫描验证   ←──  安装完成
```

脚本是诊断工具，Claude AI 是安装智能。遇到脚本不认识的工具，AI 会用自身知识甚至搜索来解决。

### 自定义依赖

在 `~/.claude-sync/postinstall.sh` 中添加自定义安装步骤：

```bash
#!/usr/bin/env bash
# 示例：安装额外工具
brew install jq ripgrep
pip install some-package
```

该脚本会在 `/sync deps install` 时自动执行。

## 架构

本方案涉及两个 Git 仓库：

```
┌──────────────────────────────────────────────┐
│  项目仓库（本仓库，可公开）                     │
│  claude-config-sync                          │
│                                              │
│  内容: sync.sh, install.sh, SKILL.md, README │
│  用途: 分发工具本身                            │
└──────────────┬───────────────────────────────┘
               │ install.sh
               ▼
┌──────────────────────────────────────────────┐
│  配置仓库（必须私有）                           │
│  ~/.claude-sync/                             │
│                                              │
│  内容: CLAUDE.md, settings.json, mcp.json,   │
│        agents/, skills/, plugins 元数据       │
│  用途: 你自己的多台机器间同步个人配置            │
└──────────────┬───────────────────────────────┘
               │ /sync
               ▼
┌──────────────────────────────────────────────┐
│  ~/.claude/                                  │
│  Claude Code 实际使用的配置目录                 │
└──────────────────────────────────────────────┘
```

**项目仓库是工具，配置仓库是数据。** 安装一次项目仓库，之后所有操作通过 `/sync` 命令完成。

## 安全提醒

- 配置仓库**必须设为私有**
- `settings.local.json` 不会被同步（包含密码、权限规则等）
- 如果 `settings.json` 或 `mcp.json` 中有 API Key，建议改用环境变量
- 所有同步通过你自己的 Git 仓库进行，不经过第三方

## 许可证

[MIT](LICENSE)
