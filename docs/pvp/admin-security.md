# 管理员与客户端 MOD 策略

## 身份分离

管理员判断集中在 [`admin/privileges.lua`](../../pvp/scripts/src/admin/privileges.lua)，OB 判断集中在 [`observer/privileges.lua`](../../pvp/scripts/src/observer/privileges.lua)。两者是独立身份:

- 管理员可以不是 OB。
- OB 可以不是管理员。
- 观察、全图、队伍聊天旁观和血条接收只属于 OB。
- 服务器管理、统一锁和管理动作只属于管理员。

## RPC 权限

[`core/rpc.lua`](../../pvp/scripts/src/core/rpc.lua) 将动作分组后再调用 [`observer/actions.lua`](../../pvp/scripts/src/observer/actions.lua)。

OB 动作:

- `chuansong`: 地图传送。
- `ditu`: 强制重新获取地图。

管理员动作:

- `give_team_item`: 给指定红队或蓝队发木手杖。
- `wanjia`: 传送到玩家、复活鬼魂或处死玩家。
- `youxi`: 解除开局暂停，或调用服务器暂停切换。
- `zhaoji`: 召集玩家到管理员附近。

所有服务端 RPC 都必须再次验证身份，不能只依赖客户端按钮是否可见。

## 队伍管理

- 自动分队命令要求管理员权限。
- 管理员和普通玩家一样参与分队，筛选依据是当前队伍，不依据管理员身份。
- 统一锁只禁止非管理员自行改队。
- 自动分队不受统一锁限制。

`is_excluded_from_auto_team` 当前没有调用点，是旧策略遗留接口。后续清理时可以删除，但新代码不应引用它。

## 客户端 MOD 策略

客户端 MOD 策略分为两个加载阶段:

1. [`modworldgenmain.lua`](../../pvp/modworldgenmain.lua) 在服务端调用原生 `KnownModIndex:DisableClientMods(true)`，使服务器列表发布 `client_mods_disabled`。
2. 客户端连接时由原版 `networking.lua` 临时禁用全部 client-only MOD，再重新加载服务器要求的 Bird PVP。
3. Bird PVP 加载时读取当前用户的 client table。普通玩家保持原生禁用状态；管理员原本启用的 client-only MOD 被追加回当前 `ModManager.mods` 加载队列。
4. [`client_mod_check.lua`](../../pvp/scripts/src/security/client_mod_check.lua) 只负责控制台权限和加载结果日志，不再二次修改 ModIndex，也不再使用客户端上报执行封禁。

普通玩家:

- 所有 client-only MOD 由原版连接流程临时禁用。
- 服务器要求的 MOD 正常加载。
- 客户端控制台命令被静默阻止。

管理员:

- 保留客户端控制台命令。
- `ADMIN_CLIENT_MODS` 开启时，原本启用的 client-only MOD 按优先级追加到加载队列，并继续走原版 `modworldgenmain.lua`、`modmain.lua`、Prefab 和 PostInit 流程。
- `ADMIN_CLIENT_MODS` 关闭时，管理员与普通玩家一样保持原生禁用状态，但管理员控制台权限不受影响。
- 本地 MOD 会晚于服务器 MOD 加载，不能依赖在 Bird PVP 之前修改相同接口。

## 已知边界

- 专服管理员身份在加载时优先读取原生 `GetIsServerAdmin`，再回退到 client table；若日志显示 `administrator reload skipped`，本次连接不会恢复管理员本地 MOD。
- 管理员增量加载依赖原版 `kleiregistermods` 支持追加环境，更新游戏版本后必须重新测试。
- 原生 `client_mods_disabled` 可能在连接前显示“客户端 MOD 已禁用”提示，该提示发生在 Bird PVP 加载之前，无法由本 MOD 静默处理。
- 客户端代码不能成为强安全边界；涉及伤害、物品和权限的关键操作仍必须由服务端验证。
- 修改策略后必须分别测试普通玩家、客户端房主、专服管理员和非管理员连接。
