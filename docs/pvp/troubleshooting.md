# 排错手册

## 调试日志

[`core/debug.lua`](../../pvp/scripts/src/core/debug.lua) 是唯一日志出口，统一前缀为:

```text
[BirdPVP][scope]
```

日志分为三类:

- `debug_log.log`: 仅在 `modinfo.lua` 版本包含 `beta` 时输出。
- `debug_log.info`: 所有版本输出，用于必要的运行和安全信息。
- `debug_log.error`: 所有版本输出，格式为 `[BirdPVP][scope][error]`。

常用 scope:

| scope | 含义 |
| --- | --- |
| `team-sync` | 地上权威表、持久化、预选发布、自动分队 |
| `team-shard` | 地上与地下快照请求和应用 |
| `team-apply` | 玩家 `pending/ready` 解析和队伍效果应用 |
| `team-fx` | 红蓝队脚下队伍圈生成 |
| `observer-camera` | OB 启用、地图获取、传送 |
| `client-mod-check` | 原生客户端 MOD 禁用、管理员追加加载和加载结果 |
| `lobby` | 预选倒计时开始、结束和准备状态输出 |
| `match` | 比赛参与者、结算、重生世界和异常 |
| `wx78-qa-guard` | WX-78 快捷宣告兼容保护异常 |

排查队伍问题时，应同时取得地上服务端日志、地下服务端日志和出问题玩家的客户端日志。

## 队伍未生效

按顺序查找:

1. `team-sync loaded/publish` 是否包含该 `userid=team`。
2. 玩家生成时是否出现 `team-apply player post init`。
3. 是否从 `pending` 进入 `resolved` 和 `ready broadcast`。
4. 红蓝队是否出现 `team-fx spawn/spawned`。
5. 地下是否出现 `team-shard snapshot requested/applied`。

如果一直 `pending`，优先修复权威表或迁移同步，不要添加默认红队、蓝队或 OB 兜底。错误兜底会造成串队聊天和敌方地图位置泄露。

## 有队伍但没有队伍圈

- 确认队伍是 `1` 或 `2`，OB 和等待不会生成圈。
- 查看 `team-fx spawn failed`。
- 确认 [`bird_duiwufx.lua`](../../pvp/scripts/prefabs/bird_duiwufx.lua) 的 prefab 名与组件一致。
- 确认 [`bird_duiwufx.zip`](../../pvp/anim/bird_duiwufx.zip) 内动画 bank 仍叫 `bird_duiwufx`。
- 替换动画 ZIP 后彻底重启客户端和服务器，DST 会缓存动画资源。

## 上下洞后队伍错误

- 地上必须是唯一权威，地下不得写持久化表。
- 下洞前组件存档应包含 `bird_team`。
- 地下玩家应先从 `component-preseed` ready，再由 `shard-snapshot` 校正。
- 若快照未到，地图和聊天应保持 pending，而不是显示全部玩家。

## OB 未启用或误启用

- `team-apply ready broadcast ... team 0` 后才应启用 camera shell。
- 红蓝队 ready 后必须调用 `observer_camera.disable`。
- 检查是否直接读取了旧 `duiwu` 或管理员身份。
- OB 权限丢失但下洞恢复，通常说明地上玩家生成时权威表尚未 ready 或 ready 事件未应用。

## 原版组件 nil 崩溃

典型报错位置:

- `statusdisplays.health`
- `sanity_replica._isinsanitymode`
- `craftingmenu_ingredients.inventory`
- `playercontroller.combat`
- `SGwilson.burnable`
- `playervision.inventory`

这类问题通常是 OB 模式删除了原版假定存在的组件。先恢复组件，不要继续给每个原版调用点打补丁。允许删除的组件清单见 [OB 模式](observer-mode.md)。

## 聊天发送不出去

- 检查玩家是否仍为 `pending`。
- 确认 `ChatHistory:AddToHistory` 参数签名没有被其他 MOD 覆盖。
- 队伍消息必须由内部 `/d` 前缀编码，普通消息不要手工加前缀。
- 暂停不应阻止队伍 netvar dirty 事件和客户端 UI 更新。
- `[T]` 队伍消息由服务端按权威队伍通过 Client RPC 定向发送，同队成员和 OB 可接收；敌方客户端的 `client_chat_log.txt` 不应出现该消息。`[A]` 仍是主动发送的全局消息。

## 大厅未选角色导致崩溃

开始游戏流程不能对仍停留在初始选人页、没有有效角色 loadout 的玩家推送进入世界事件。应在 [`preselect.lua`](../../pvp/scripts/src/lobby/preselect.lua) 和 [`worldcharacterselectlobby.lua`](../../pvp/scripts/components/worldcharacterselectlobby.lua) 的准备状态处阻止启动，而不是伪造 `skins` 表掩盖问题。

## 暂停问题

需要区分两种状态:

- 预选大厅期间的世界时钟暂停。
- `START_PAUSE_DURATION` 控制的开局暂停和自动开始倒计时。

开局倒计时完成后，玩家进入世界时尝试执行一次暂停。服务端同时监听 `ms_playerjoined` 和 `ms_playerspawn`，重复事件由内部状态阻止重复启动倒计时。

房主服和专用服务器都使用原生 `TheNet:SetServerPaused`。纯专用服务器的原生暂停通常要求至少有一名管理员在线；没有管理员时暂停可能不会生效，逻辑会在检测到服务器仍未暂停后结束本次自动暂停。

开局暂停可由静态倒计时自动解除，也可由管理员操作 `youxi` 或 `ReleaseStartPause` 提前解除。若解除后再次暂停，搜索 `SetServerPaused`、`SetStartServerPaused` 和 `ApplyStartPause` 的调用，不要增加周期“保持暂停”任务。

## 客户端 MOD 检查

- 普通玩家本地 MOD 仍被加载: 完整返回主菜单后重新进入世界，前端日志应输出 `native client mods disabled injected=true`。缺失或为 `false` 表示原生状态没有在创建服务器前成功设置。
- 原生禁本地生效后，普通玩家客户端日志中的本地 MOD 应显示 `temp_disabled=true`、`loaded=false`。
- 管理员本地 MOD 未恢复: 检查是否输出 `administrator reload skipped`；这表示 Bird PVP 加载时管理员身份尚不可用。
- 日志显示 `disabled by configuration`: `ADMIN_CLIENT_MODS` 已关闭，属于预期行为。
- 管理员追加成功: 应依次看到 `administrator client mod queued`、`administrator client mods registered`，进入 HUD 后对应 MOD 应为 `loaded=true`、`admin_reloaded=true`。
- 出现 `administrator registration failed`: 保存完整客户端日志，重点检查 `kleiregistermods` 错误；该次连接会撤销新增环境，不继续加载半初始化 MOD。
- 原生“客户端 MOD 已禁用”弹窗发生在 Bird PVP 加载前，属于预期行为。
