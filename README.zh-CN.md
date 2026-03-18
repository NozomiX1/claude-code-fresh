# cc-fresh

**Claude Code 插件自动更新工具** — 让你的插件始终保持最新。

cc-fresh 在每次会话启动时静默运行，检查所有已安装的 marketplace 是否有插件更新，对配置了自动更新的 marketplace 直接应用更新，其余的则通过通知提醒你。再也不用手动检查插件是否过时了。

## 功能特性

- **自动检测更新** — 每次会话启动时拉取远端 marketplace 状态，与本地安装版本对比
- **按插件目录精确计数** — 仅统计影响到具体插件目录的 commit，而非整个 marketplace 仓库
- **智能通知** — 可配置冷却时间（默认 24 小时），避免对同一批待更新插件重复提醒
- **自动更新模式** — 设为 `auto` 策略的 marketplace 无需任何交互即可拉取并应用更新
- **缓存优化** — 结果缓存 1 小时，避免快速重启会话时重复执行 git 操作
- **版本号 + SHA 双轨追踪** — 同时支持语义化版本号和无版本号（基于 commit）的插件

## 环境要求

- **bash** 3.2+（macOS 自带版本即可）
- **python3**（用于 JSON 处理）
- **git**（用于拉取 marketplace 更新）

## 安装

```bash
# 1. 添加此仓库为 marketplace
/plugin marketplace add NozomiX1/claude-code-fresh

# 2. 安装插件
/plugin install cc-fresh@claude-code-fresh
```

安装后，cc-fresh 会在下次启动 Claude Code 会话时自动生效。

## 工作原理

### 会话启动流程

每次启动新的 Claude Code 会话时，cc-fresh 执行以下流程：

```
会话启动
    │
    ▼
[缓存是否有效？] ── 是 ──► 使用缓存结果
    │ 否
    ▼
git fetch 所有 marketplace
    │
    ▼
对比远端 vs 本地安装
（版本号 + commit SHA）
    │
    ▼
写入 cache.json
    │
    ▼
[有 "auto" 策略？] ── 是 ──► 拉取并应用更新
    │                            │
    ▼                            ▼
[冷却时间已过？] ── 是 ──► 输出通知
    │ 否
    ▼
 （静默）
```

1. **缓存检查** — 如果 `cache.json` 存在且不超过 1 小时，跳过 git fetch。
2. **更新检测** — 对每个已安装插件，将本地版本/SHA 与远端 marketplace 状态比较。commit 计数精确到每个插件的子目录。
3. **自动更新** — `auto` 策略的 marketplace 中的插件会立即拉取并安装，缓存就地更新（而非删除），保证后续检查仍然高效。
4. **通知** — 如果还有剩余更新（非 auto 的 marketplace），输出一行通知，受冷却规则约束。

### 通知冷却机制

cc-fresh 会对待更新列表计算哈希值。通知在以下情况触发：

- 首次检测到更新，**或者**
- 待更新集合发生变化（新插件、新版本），**或者**
- 距离上次通知已超过冷却时间（默认 24 小时）

这意味着你不会每次打开会话都看到同一条"3 个插件有更新"的消息。

## 命令

| 命令 | 说明 |
|---|---|
| `/cc-fresh:check` | 检查所有 marketplace 的插件更新并展示结果 |
| `/cc-fresh:update` | 应用上次检查发现的所有待更新插件 |
| `/cc-fresh:config` | 查看和修改更新策略、冷却时间及各 marketplace 设置 |

### `/cc-fresh:check`

展示所有插件的状态摘要：

```
Updates available:
  context7       1.0.0 → 1.1.0     (official-marketplace)    2 commits behind
  my-tool        a1b2c3d4e5f6 → f6e5d4c3b2a1  (community)   5 commits behind

Up to date:
  plugin-a, plugin-b, plugin-c

Ignored:
  experimental-plugin (test-marketplace)

Run /cc-fresh:update to apply updates.
Run /cc-fresh:config to change update policies.
```

### `/cc-fresh:update`

从每个 marketplace 仓库拉取最新代码，将更新的插件文件复制到本地插件目录，并更新 `installed_plugins.json` 中的版本/SHA 记录。

更新完成后，运行 `/reload-plugins` 使更改在当前会话生效。

### `/cc-fresh:config`

交互式配置管理。展示所有已知 marketplace 及其当前策略，并允许修改：

```
cc-fresh Configuration:

  Default policy: check
  Notification cooldown: 24 hours

  Marketplace policies:
    1. official-marketplace    auto
    2. community-plugins       (default)
    3. test-marketplace        ignore

Available policies:
  auto   - 会话启动时自动拉取并应用更新
  check  - 仅检查更新并通知（默认）
  ignore - 完全跳过此 marketplace
```

## 配置

配置文件位置：`~/.claude/cc-fresh/config.json`

首次会话启动时自动创建，默认内容如下：

```json
{
  "default": "check",
  "cooldown_hours": 24,
  "marketplaces": {}
}
```

### 字段说明

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `default` | string | `"check"` | 未设置显式覆盖的 marketplace 使用的默认策略 |
| `cooldown_hours` | number | `24` | 对同一批更新重复通知的间隔小时数 |
| `marketplaces` | object | `{}` | 按 marketplace 设置的策略覆盖（稀疏存储，仅记录显式覆盖） |

### 策略说明

| 策略 | 行为 |
|---|---|
| `auto` | 会话启动时自动拉取远端状态、pull 代码并应用更新 |
| `check` | 拉取远端状态并通知可用更新，但不自动应用 |
| `ignore` | 完全跳过此 marketplace — 不 fetch、不通知 |

### 示例：为受信任的 marketplace 启用自动更新

```json
{
  "default": "check",
  "cooldown_hours": 24,
  "marketplaces": {
    "official-marketplace": "auto"
  }
}
```

也可以通过 `/cc-fresh:config` 交互式修改。

## 项目结构

```
cc-fresh/
├── plugin/
│   ├── .claude-plugin/
│   │   └── plugin.json          # 插件元数据
│   ├── hooks/
│   │   └── hooks.json           # SessionStart hook 定义
│   ├── scripts/
│   │   ├── helpers.sh           # 共享工具函数（JSON、配置、marketplace）
│   │   ├── session-start.sh     # 入口 — 编排检查 + 自动更新流程
│   │   ├── check-updates.sh     # 核心检测 — git fetch + 版本比较
│   │   └── do-update.sh         # 应用更新 — git pull + 文件复制
│   └── skills/
│       ├── check/SKILL.md       # /cc-fresh:check 命令
│       ├── update/SKILL.md      # /cc-fresh:update 命令
│       └── config/SKILL.md      # /cc-fresh:config 命令
├── tests/
│   ├── setup-test-env.sh        # 测试夹具生成器
│   ├── test-helpers.sh          # helpers.sh 单元测试
│   ├── test-check-updates.sh    # 更新检测集成测试
│   ├── test-do-update.sh        # 更新执行集成测试
│   └── test-session-start.sh    # 会话 hook 集成测试
├── README.md                    # English
├── README.zh-CN.md              # 中文
└── LICENSE
```

## 运行测试

所有测试都是独立的 bash 脚本，会创建临时的模拟环境：

```bash
# 逐个运行
bash tests/test-helpers.sh
bash tests/test-check-updates.sh
bash tests/test-session-start.sh
bash tests/test-do-update.sh

# 一次性全部运行
for t in tests/test-*.sh; do echo "--- $t ---"; bash "$t"; echo; done
```

测试会创建隔离的临时目录，包含模拟的 git 仓库和 marketplace 结构，不会影响你的真实插件安装。

## 数据文件

cc-fresh 的运行时数据存储在 `~/.claude/cc-fresh/`：

| 文件 | 用途 |
|---|---|
| `config.json` | 用户配置（策略、冷却时间） |
| `cache.json` | 缓存的更新检查结果（TTL: 1 小时） |
| `notify-state.json` | 上次通知的时间戳和哈希值（用于冷却判断） |

## 许可证

MIT
