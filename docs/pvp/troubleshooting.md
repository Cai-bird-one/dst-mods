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

排查队伍问题时，应同时取得地上服务端日志、地下服务端日志和出问题玩家的客户端日志。

## 第一天武器打人掉血，但没有僵直

- **现象**：第一天持武器攻击玩家仍会扣血，受击动作却被挡住。规则应为玩家之间仅允许真正空手的人形拳击；持物品、变身攻击和玩家随从攻击仍受第一天保护限制。
- **原因**：本机 DST 构建 `759671` 的 `combat:GetAttacked` 已改为转发到 `GetAttacked_Internal`，而 `DoAttack`、`DoAreaAttack` 直接调用内部入口。旧保护只包装公开的 `GetAttacked`，普通攻击因此绕过免伤；独立的 `wilson` 状态图 `attacked` 保护继续生效，形成“有伤害、没僵直”。
- **处理**：[`protection/player.lua`](../../pvp/scripts/src/protection/player.lua) 在服务端玩家初始化时优先包装 `GetAttacked_Internal`；旧构建无此方法时回退到 `GetAttacked`。在扣血、护甲损耗和受击事件之前拦截，并完整透传未拦截攻击的 `spdamage`、`from_doattack` 等参数。继续使用世界 `cycles < 1` 判定，第二天自动恢复；Master 与 Caves 均注册此保护。
- **验证**：[`first_day_protection.py`](../../tools/pvp/tests/first_day_protection.py) 通过 Python + Lupa 的 Lua 5.1 运行本机 ZIP 中的原版战斗方法及完整保护脚本，使用桩对象模拟引擎和原状态图反应。修复前 `836fccb` 基线的 11 项断言复现扣血但无受击动作，修复后 214 项断言通过，覆盖普攻、范围、公开/内部入口、拳头、手持工具、变身、随从、第二天、野怪、OB、参数透传、旧入口回退及客户端不装服务端 Hook。真实客户端未实测；重启加载修改后，仍需在地上、地下验证第一天武器攻击无伤害无僵直、拳头正常，以及第二天武器伤害恢复。
- **证据**：本机 `data/databundles/scripts.zip` 内 `scripts/components/combat.lua` 的 `GetAttacked`、`GetAttacked_Internal`、`DoAttack`、`DoAreaAttack`；`scripts/components/projectile.lua` 的命中处理也调用 `DoAttack`。受击状态图与免伤入口是两条独立保护，不能仅凭无僵直判定免伤已经生效。

在仓库根目录执行 `python tools/pvp/tests/first_day_protection.py`。若 Lupa 安装在临时目录，加 `--lupa-path <目录>`；需要同时重现旧问题时加 `--baseline-ref 836fccb`。测试不启动游戏或修改存档。

针对其他 Hook 的后续核对见 [DST 759671 兼容性审计](compatibility-759671.md)，其中记录位面屏蔽、血条、WX-78、旋风杖、聊天静默参数和开局等待配置的修复与验证；这些后续修复从 `1.0beta.28` 开始提供。

## 禁用的位面伤害重新生效

- **现象**：规则要求移除位面伤害，但新版普通攻击、范围攻击仍附带位面伤害；公开 `GetAttacked` 调用却能正常屏蔽。
- **原因**：[`health_bar.lua`](../../pvp/scripts/src/ui/health_bar.lua) 旧包装通过不传 `spdamage` 来屏蔽伤害，新版内部结算入口绕过了包装，也绕过了同处的血条触发。
- **处理**：优先包装 `GetAttacked_Internal`，旧构建回退到公开入口；仅移除伤害表副本中的 `planar`，过滤后无其他类型则传 `nil`。保留普通伤害、其他特殊类型、`from_doattack` 等尾参和原返回值，同时恢复内部入口的血条触发。Master、Caves 的全部服务端 combat 组件生效，客户端不安装此包装。
- **验证**：[`planar_damage.py`](../../tools/pvp/tests/planar_damage.py) 加载本机原版战斗方法、完整血条及玩家保护脚本。`2de57b9` 基线的 16 项断言复现泄漏；修复后 527 项断言通过，覆盖公开/内部/普攻/两种范围入口、玩家与生物、混合和纯位面伤害、共享表、其他特殊类型、尾参和返回值、旧入口回退、客户端排除、首日保护叠加、无扣血时血条触发、重定向及反伤。另有原先的第一天保护 214 项断言继续通过。这些均为 Lua 5.1 隔离模拟，未做真实客户端联机验证。
- **证据**：本机 `759671` 的 `components/combat.lua`、`components/spdamageutil.lua`。原版特殊伤害表支持第三方扩展，不能简单丢弃整个 `spdamage`；也不能直接修改可能被多个目标共用的输入表。

运行 `python tools/pvp/tests/planar_damage.py --baseline-ref 2de57b9`，Lupa 位于临时目录时同样加 `--lupa-path <目录>`。重新启动加载本地修改后，应在地上和地下确认混合攻击只扣普通伤害、纯位面不扣血，以及 OB 血条正常刷新。

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
