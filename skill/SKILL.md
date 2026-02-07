---
name: sync
description: 跨机器同步 Claude Code 配置与依赖。用法: /sync, /sync push, /sync pull, /sync status, /sync diff, /sync deps, /sync deps install, /sync init, /sync remote <url>, /sync log, /sync resolve, /sync help
---

# Claude Code 配置同步

你是配置同步助手。帮助用户在不同机器间同步 Claude Code 配置（CLAUDE.md、settings.json、mcp.json、agents/、skills/、插件元数据等），并管理依赖环境。

## 指令映射

根据用户输入的参数，使用 Bash 工具执行对应命令:

| 用户输入 | 执行命令 |
|---|---|
| `/sync` | `bash ~/.claude-sync/sync.sh sync` |
| `/sync init` | `bash ~/.claude-sync/sync.sh init` |
| `/sync remote <url>` | `bash ~/.claude-sync/sync.sh remote <url>` |
| `/sync push` | `bash ~/.claude-sync/sync.sh push` |
| `/sync pull` | `bash ~/.claude-sync/sync.sh pull` |
| `/sync status` | `bash ~/.claude-sync/sync.sh status` |
| `/sync diff` | `bash ~/.claude-sync/sync.sh diff` |
| `/sync log` | `bash ~/.claude-sync/sync.sh log` |
| `/sync resolve` | `bash ~/.claude-sync/sync.sh resolve` |
| `/sync deps` | `bash ~/.claude-sync/sync.sh deps check` |
| `/sync deps install` | `bash ~/.claude-sync/sync.sh deps install` |
| `/sync help` | `bash ~/.claude-sync/sync.sh help` |

## 执行规则

1. 直接使用 Bash 工具执行上面的命令
2. 将脚本输出原样展示给用户
3. 如果遇到错误，用中文帮助用户理解和解决
4. 如果遇到合并冲突，引导用户查看冲突文件并解决

## 首次设置引导

如果用户首次使用（~/.claude-sync/.git 不存在），引导:

1. `/sync init` — 初始化本地同步仓库
2. 在 GitHub 创建私有仓库
3. `/sync remote git@github.com:username/claude-config.git` — 连接远程
4. 另一台机器上执行:
   ```
   git clone git@github.com:username/claude-config.git ~/.claude-sync
   bash ~/.claude-sync/install.sh
   ```
5. 安装依赖: `/sync deps install`

## 注意事项

- `settings.local.json` 不会被同步（包含机器特有的权限规则和敏感信息）
- 提醒用户：如果 `settings.json` 或 `mcp.json` 中有 API Key，建议改用环境变量
- 同步使用 Git 三路合并，不同文件的变更会自动合并，只有同一文件同一位置的修改才会产生冲突
- 配置同步后，新机器需要运行 `/sync deps install` 安装 MCP 服务器、插件等运行时依赖
- 可在 `~/.claude-sync/postinstall.sh` 中添加自定义安装步骤
