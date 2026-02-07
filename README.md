# Claude Code Config Sync

通过 Git 在不同机器间同步 Claude Code 的配置文件。

这是一个 [Claude Code Skill](https://docs.anthropic.com/en/docs/claude-code/skills) 插件，安装后可以在 Claude Code 中直接使用 `/sync` 命令进行配置同步。

## 功能特性

- **双向智能同步** -- 基于 Git 三路合并，自动处理多台机器的配置变更
- **一键操作** -- 在 Claude Code 中输入 `/sync` 即可完成同步
- **冲突检测** -- 自动检测冲突并引导用户解决
- **选择性同步** -- 只同步通用配置，跳过机器特有的本地设置
- **备份安全** -- 安装时自动备份已有的配置文件
- **Skill 集成** -- 作为 Claude Code Skill 运行，无需离开对话界面

## 同步范围

### 会同步的配置

| 文件/目录 | 说明 |
|-----------|------|
| `CLAUDE.md` | 全局自定义指令 |
| `settings.json` | Claude Code 设置 |
| `mcp.json` | MCP 服务器配置 |
| `keybindings.json` | 快捷键绑定 |
| `agents/` | 自定义 Agent 定义 |
| `skills/` | Skill 插件（包括本插件自身） |

### 不会同步的配置（机器特有）

| 文件/目录 | 说明 |
|-----------|------|
| `settings.local.json` | 本地权限规则、敏感信息 |
| `.credentials/` | 认证凭据 |
| `statsig/` | 统计数据 |
| `session-env/` | 会话环境 |
| `todos/` | 待办事项 |
| `debug/` | 调试日志 |

## 安装方法

### 首台机器

```bash
# 1. 克隆项目仓库
git clone https://github.com/username/claude-config-sync.git

# 2. 运行安装脚本
bash claude-config-sync/install.sh

# 3. 在 Claude Code 中设置远程配置仓库
#    先在 GitHub 创建一个私有仓库（例如 claude-config），然后：
/sync remote git@github.com:username/claude-config.git
```

安装脚本会自动：
- 复制 `sync.sh` 到 `~/.claude-sync/sync.sh`
- 复制 `skill/SKILL.md` 到 `~/.claude/skills/config-sync/SKILL.md`
- 初始化 `~/.claude-sync/` 为 Git 仓库
- 将当前 `~/.claude/` 中的配置做初始提交

### 第二台机器

```bash
# 1. 克隆配置仓库（不是项目仓库）
git clone git@github.com:username/claude-config.git ~/.claude-sync

# 2. 运行安装脚本（配置仓库中自带）
bash ~/.claude-sync/install.sh
```

安装脚本会自动检测到已有配置仓库，将远程配置同步到本地 `~/.claude/`。

> **注意**: 第二台机器克隆的是你的**配置仓库**（`claude-config`），不是这个项目仓库（`claude-config-sync`）。

## 使用方法

所有操作都在 Claude Code 对话中完成，输入以 `/sync` 开头的命令即可。

### 日常同步

```
/sync              智能双向合并（推荐日常使用）
/sync push         仅推送本地变更到远程
/sync pull         仅拉取远程变更到本地
```

### 查看状态

```
/sync status       同步状态总览（本地变更、远程状态）
/sync diff         查看具体文件差异
/sync log          查看同步历史记录
```

### 首次设置

```
/sync init         初始化本地同步仓库
/sync remote <url> 设置远程仓库地址
```

### 冲突处理

```
/sync resolve      解决冲突后完成合并
```

### 帮助

```
/sync help         查看所有可用命令
```

## 合并策略

`/sync` 命令使用 Git 三路合并（3-way merge）策略：

1. **收集** -- 将 `~/.claude/` 的配置复制到 `~/.claude-sync/` 仓库
2. **提交** -- 将本地变更提交到 Git
3. **合并** -- 拉取远程变更，与本地进行三路合并
4. **推送** -- 将合并结果推送到远程
5. **应用** -- 将最终结果同步回 `~/.claude/`

**自动合并**: 如果两台机器修改了不同的文件（或同一文件的不同位置），Git 会自动合并，无需人工干预。

**冲突处理**: 如果两台机器修改了同一文件的同一位置，会产生冲突。此时脚本会提示你手动编辑冲突文件，解决后运行 `/sync resolve` 完成合并。

## 两个仓库的关系

本方案涉及两个 Git 仓库，作用不同：

### 项目仓库 (`claude-config-sync`)

- **是什么**: 就是你正在看的这个仓库
- **内容**: 安装脚本、同步脚本、Skill 定义、文档
- **用途**: 分发工具本身，其他人可以 fork 使用
- **是否私有**: 可以公开

### 配置仓库 (`claude-config`)

- **是什么**: 存储你的实际 Claude Code 配置的仓库
- **内容**: `CLAUDE.md`、`settings.json`、`mcp.json`、`skills/`、`agents/` 等
- **用途**: 在你自己的多台机器间同步配置
- **是否私有**: **必须私有**（包含个人配置和偏好设置）
- **位置**: 安装后位于 `~/.claude-sync/`

简单来说：**项目仓库是工具，配置仓库是数据**。你只需要安装一次项目仓库，之后所有同步操作都通过配置仓库进行。

## 安全提醒

- 配置仓库**必须设为私有**，因为可能包含个人偏好和工作流信息
- `settings.local.json` 不会被同步，其中可能包含敏感的权限规则
- 如果 `settings.json` 或 `mcp.json` 中包含 API Key，建议改用环境变量引用
- 同步脚本不会传输任何数据到第三方，所有同步通过你自己的 Git 仓库进行

## 许可证

[MIT](LICENSE)
