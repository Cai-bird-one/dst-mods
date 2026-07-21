# 总体架构

## 启动链

运行入口为 [`pvp/modmain.lua`](../../pvp/modmain.lua):

```text
modmain.lua
  -> scripts/src/init.lua
  -> scripts/src/pvp.lua
  -> team / observer / protection / gameplay / world
  -> lobby / security / ui / core/rpc
```

`modmain.lua` 只做两件事:

1. 让 MOD 环境通过元表读取 `GLOBAL`。
2. 使用 `modimport` 加载 `scripts/src/init.lua`。

[`init.lua`](../../pvp/scripts/src/init.lua) 读取版本号。版本字符串包含 `beta` 时，设置 `BIRD_PVP_DEBUG = true`，启用 `[BirdPVP]` 调试日志。

## 日志规范

运行时日志统一通过 [`core/debug.lua`](../../pvp/scripts/src/core/debug.lua) 输出，业务模块不要直接调用 `print`:

- `debug_log.log(scope, ...)`: 调试信息，仅在版本号包含 `beta` 时输出。
- `debug_log.info(scope, ...)`: 正式版也需要保留的运行和安全信息。
- `debug_log.error(scope, ...)`: 正式版也需要保留的异常信息，前缀末尾包含 `[error]`。

`debug.lua` 是唯一允许直接调用 `print` 的日志后端。新增日志应复用已有 scope；只有职责确实不同的模块才增加新 scope。

## 加载顺序

[`pvp.lua`](../../pvp/scripts/src/pvp.lua) 的顺序具有依赖意义:

1. `team.lua`: 先注册队伍状态、队伍组件和聊天。
2. `observer.lua`: OB 权限依赖队伍状态。
3. `protection.lua`: 保护规则依赖 OB 判定。
4. `gameplay.lua`、`world.lua`: 注册玩法和世界规则。
5. `lobby.lua`: 按配置注册预选大厅。
6. `security.lua`: 安装客户端 MOD 策略。
7. `ui.lua`: 安装大厅、血条和计分板 UI。
8. `core/rpc.lua`: 最后注册动作路由，动作模块已可用。

新增跨模块依赖时，应优先消除循环依赖；确实依赖注册顺序时，在入口注释中写明原因。

## `modimport` 与 `require`

两者不能随意互换。

### 使用 `modimport`

以下脚本需要 MOD 环境里的注册函数，应由入口脚本 `modimport`:

- 调用 `AddPlayerPostInit`、`AddPrefabPostInit`、`AddComponentPostInit`。
- 调用 `AddClassPostConstruct`、`AddModRPCHandler`、`AddUserCommand`。
- 修改 `PrefabFiles`、`Assets` 等 MOD 环境字段。

路径从 MOD 根目录计算，因此写作:

```lua
modimport("scripts/src/team/component.lua")
```

### 使用 `require`

可复用模块放在 `pvp/scripts/` 下，通过 Lua 模块路径加载:

```lua
local team_state = require("src/team/lobby_team_state")
```

适合 `require` 的模块包括:

- 常量和状态查询。
- 权限判断。
- 无注册副作用的动作函数。
- 被多个注册脚本共享的辅助模块。

不要让 `require` 模块在加载阶段直接依赖 `AddComponentPostInit` 等 MOD 环境函数。此前血条拆分时出现的 `nil env` 问题，就是混用了这两类加载方式。

## 目录职责

```text
pvp/
  modinfo.lua              配置和创意工坊元数据
  modmain.lua              极小运行入口
  modworldgenmain.lua      世界生成入口
  anim/                    发布用动画包
  announcestrings/         宣告文本
  scripts/components/      DST 组件
  scripts/prefabs/         DST Prefab
  scripts/widgets/         DST Widget
  scripts/src/             按功能拆分的业务模块
```

仓库级内容不放在 `pvp/`:

```text
docs/                      维护文档
tools/pvp/                 开发工具和原始资源
```

## 新增功能的落点

- 新规则优先放入现有领域目录，例如 `team/`、`observer/`、`ui/`。
- 只有需要 DST 组件生命周期时才新增 `scripts/components/` 文件。
- 只有需要网络实体或动画实体时才新增 `scripts/prefabs/` 文件。
- 入口文件只负责加载，不承载业务逻辑。
- 网络协议、事件名和队伍编号应集中复用，不在 UI 中另写一套判断。
