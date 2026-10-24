# DST 759671 与 PVP 1.0beta.27 兼容性核对

核对日期：2026-10-24。初次核对对象为本机 `data/databundles/scripts.zip`（游戏构建 `759671`）与 `pvp/` 的 `1.0beta.27`。以下六项均已修复并收录于 `1.0beta.28`，对应离线验证通过；未做真实客户端联机验证。创意工坊发布回执见 [发布记录](release.md)。

第一天普通攻击绕过免伤的问题已由 `f7cf456` 修复。本轮继续检查其他 Hook 是否依赖旧入口、旧参数或旧 UI 数据结构。缺少旧游戏构建时，不根据模组代码的提交时间断定游戏行为何时改变。

## 与当前战斗入口和 WX-78 UI 不匹配

### 位面伤害屏蔽被新结算入口绕过（1.0beta.28 已修复）

- **设计要求**：用户于 2026-10-24 确认，PVP 本来就要删除位面伤害。公开入口将位面伤害过滤掉符合设计；此前将其列为“应恢复的伤害”是审计误判，撤回该建议。
- **现象**：公开 `combat:GetAttacked` 仍过滤位面伤害，但普通攻击、范围攻击走内部入口时绕过了该过滤，导致位面伤害重新参与结算。
- **原因**：[`health_bar.lua`](../../pvp/scripts/src/ui/health_bar.lua) 的旧公开入口包装仅透传 `attacker, damage, weapon, stimuli`，未传入 `spdamage`；当前原版 `DoAttack`、`DoAreaAttack` 直接调用 `GetAttacked_Internal` 并传入 `spdamage`。原有包装从模组初始提交 `332de54` 已存在，失配点是实际结算入口。
- **处理**：包装内部结算入口，旧构建回退到公开入口；从伤害表副本中仅移除 `planar`，过滤后为空则传 `nil`。保留普通伤害、其他特殊伤害类型、`from_doattack` 等尾部参数及原返回值，不修改调用方原表。
- **修复前证据**：原版战斗函数加实际血条包装的 Lua 5.1 模拟中，公开入口的 `30 普通 + 8 位面` 扣 30、`0 普通 + 8 位面` 扣 0，均符合规则；普通 `DoAttack` 却扣 38，证明屏蔽被绕过。范围攻击同样直达内部入口的结论来自本机构建 `components/combat.lua:1321/1333` 的源码核对。
- **修复验证**：[`planar_damage.py`](../../tools/pvp/tests/planar_damage.py) 使用完整血条/保护脚本与本机原版战斗方法，旧版 16 项断言复现问题，当前 527 项断言通过。五种攻击入口均满足 `30 普通 + 8 位面` 只扣 30、纯位面不扣血，另覆盖重定向、反伤、共享表、其他特殊类型、参数透传、旧构建回退及第一天保护。原有第一天保护的 214 项断言继续通过；未做真实客户端验证。

### 血条受击入口被绕过（1.0beta.28 已修复）

- **现象**：普通攻击、范围攻击不再执行血条 `GetAttacked` 包装内的显示/刷新逻辑。发生实际扣血时，独立的 `health:DoDelta` 包装仍能显示受击者血条，因此不能说血条全部失效。
- **原因**：[`health_bar.lua`](../../pvp/scripts/src/ui/health_bar.lua) 旧代码只包装公开的 `GetAttacked`；原版 `components/combat.lua` 的 `DoAttack`、`DoAreaAttack` 改走 `GetAttacked_Internal`，与此前免伤失效属于同一种入口问题。
- **处理**：与位面屏蔽一同迁移到当前实际结算入口，旧构建回退到公开入口；保留 `DoDelta` 的数值同步。公开与内部入口不同时包装，避免同一次受击重复触发此包装。
- **修复前证据**：加载原版战斗函数及实际血条包装，用显示函数计数器验证：零伤害 `DoAttack` 不调用血条触发，公开 `GetAttacked` 则调用双方触发；普通 `30 + 8` 伤害仍由 `DoDelta` 触发受击者血条。显示函数和实体为桩，未做真实 OB 画面验证。
- **修复验证**：上述位面回归加载完整血条脚本，用附近 OB 与已有血条实体桩记录计时器更新。五种入口在无扣血时，攻击者与受击者的血条各刷新一次；普通扣血时受击者仍额外经过 `DoDelta` 更新。真实 OB 画面仍待验证。

### WX-78 快捷宣告仍按单栏旧接口读取（1.0beta.28 已修复）

- **现象**：模块快捷宣告名称缺失或错报；电量宣告可能保留 `{USED}` 占位符，扩展电量后仍以旧的 6 格为上限。
- **原因**：当前原版 `widgets/upgrademodulesdisplay.lua:370` 的签名为 `OnModuleAdded(bartype, moduledefinition_index)`，但旧 [`wx78_quick_announce_guard.lua`](../../pvp/scripts/src/ui/wx78_quick_announce_guard.lua) 将第一参数当模块 ID。[`qa_main.lua`](../../pvp/scripts/qa_main.lua) 内旧 Hook 同样依赖旧参数和旧字段。原版使用 `chip_slotsinuse[bartype]` 与 `max_energy`；旧宣告使用已不存在的 `slots_in_use` 和已被原版标记 Deprecated 的 `TUNING.WX78_MAXELECTRICCHARGE`。
- **处理**：删除旧兼容池和 `OnModuleAdded` 包装，宣告时直接读取原版芯片 `modulename` 与各栏有效索引，避免卸载、移位、复用留下过期名字或数量。电量读取 `max_energy`，占用分别显示 α/β/γ 栏槽位；补充七格消息并支持旧自定义模板缺少 `SEVEN` 的情况。模块原生方法不改，继续使用原有队聊发送函数。
- **修复前证据**：原版 `OnModuleAdded`、实际保护层和从 `qa_main.lua` 提取的旧 Hook 联合运行，Alpha 的 `maxhealth` 得到 `modname=nil`；Beta 的 `movespeed` 被记为 `maxhealth`；Gamma 的 `screech` 被记为 `maxsanity1`。原版芯片 `modulename` 始终正确。问题在快捷宣告，不据此认定原版模块安装效果或 HUD 本体损坏。
- **修复验证**：[`wx78_quick_announce.py`](../../tools/pvp/tests/wx78_quick_announce.py) 运行本机原版模块添加、卸载、移位、容量调整方法及实际加载器/宣告代码；旧版 12 项断言复现错误，当前 44 项通过。覆盖三栏模块名称/数量、复用、已有芯片、重复初始化、正常输入与返回值、红蓝队发送、独立槽位、`7/7` 和 `3/3` 满格、`6/7` 非满格、自定义模板及旧映射回退；完整 `qa_main.lua` 同时通过 Lua 5.1 编译。未做真实 UI 验证。
- **证据**：原版 `widgets/upgrademodulesdisplay.lua` 的 `OnModuleAdded`、`chip_slotsinuse`、`max_energy`，以及 `constants.lua` 的 `CIRCUIT_BARS` 和 `tuning.lua` 的旧常量说明。

## 同时发现的旧缺陷或无法确定引入时间的参数问题

### 第一天下旋风杖可借非玩家目标绕过限制（1.0beta.28 已修复）

- **现象**：直接对玩家施法会被阻止，对树或其他生物施法却会生成旋风，旋风随后仍能伤害附近玩家。
- **原因**：[`early_game.lua:12`](../../pvp/scripts/src/gameplay/early_game.lua#L12) 将 `CastSpell` 的第一参数误当施法者；原版签名是 `CastSpell(target, pos, doer)`。旋风伤害来源是 `tornado`，既不是玩家，也不是玩家 follower，因此第一天通用保护未识别其玩家归属。
- **处理**：按真实 `doer` 判断玩家施法，省略时回退到法杖 `GetGrandOwner()` / `owner`；第一天无论施法目标是谁均阻止玩家使用。已有旋风通过 `WINDSTAFF_CASTER` 与原版 `WINDSTAFF_CASTER_ISPLAYER` 归属快照阻止对玩家的伤害和受击动作，施法者离线后仍有效；野生或非玩家旋风、第二天施法不受影响。
- **验证**：[`tornado_protection.py`](../../tools/pvp/tests/tornado_protection.py) 加载实际保护脚本、本机原版 `CastSpell`、旋风生成与 `SGtornado` 伤害函数、Combat 方法，166 项 Lua 5.1 断言通过。覆盖玩家/生物目标、owner 回退、已有旋风、施法者移除、第一天/第二天、地上/地下标记、耐久不消耗、伤害和受击动作、参数返回值及客户端排除。地上/地下为模拟世界，未做实机验证；原第一天 214 项及位面 527 项回归继续通过。
- **证据与归因**：原版 `actions.lua:3457` → `components/spellcaster.lua:134` → `prefabs/staff_tornado.lua:19–24` → `stategraphs/SGtornado.lua:65–76`。错误包装从 `332de54` 已存在；归为现存隐患，不归为已证明的本次更新回归。

### 聊天包装漏传 silent（1.0beta.28 已修复）

- **现象**：近处 NPC 的部分对话本应只保存历史，但会额外触发聊天通知。
- **原因**：[`chat.lua:408`](../../pvp/scripts/src/team/chat.lua#L408) 包装 `ChatHistory:AddToHistory` 时遗漏末尾 `silent`，转发后变为 `nil`。
- **处理**：通过 `...` 透传 `text_filter_context` 后的全部参数，包括 `silent`；保持原返回值和队聊可见性过滤。
- **验证**：[`chat_history.py`](../../tools/pvp/tests/chat_history.py) 加载本机完整原版 `chathistory.lua` 和实际 PVP 聊天脚本，46 项 Lua 5.1 断言通过。静默消息仍保存历史且不通知，非静默与省略参数正常；同队、异队、pending、OB 过滤及空参数、未来参数、多返回值均保持。原旧包装已复现额外通知；未做真实客户端验证。
- **证据与归因**：原版 `components/talker.lua:70–71` 对距镜头不超过 8 的 NPC 对话传 `silent=true`。模组包装至少在 `a43fa79` 已存在，缺旧游戏源码，无法确定本次更新是否新增了这一不兼容。

### 开局等待 90/120 秒实际回退为 30 秒（1.0beta.28 已修复）

- **现象**：配置中可选择 90 或 120 秒，但实际 `START_PAUSE_DURATION` 被设为 30。
- **原因**：[`preselect.lua:4`](../../pvp/scripts/src/lobby/preselect.lua#L4) 的白名单只接受 0–60，安装大厅组件时对其他数值回退到 30；与 `modinfo.lua` 暴露的选项不一致。
- **处理**：将 90、120 加入 `START_PAUSE_DURATIONS`，与 `modinfo.lua` 的全部配置选项一致；无效值仍回退到 30。
- **验证与归因**：加载实际 `modinfo.lua` 与完整 `preselect.lua`，调用其 `forest_network` 注册回调，9 个公开选项、字符串 90/120 和无效值回退共 14 个 Lua 5.1 检查通过。倒计时组件直接读取此值，没有额外的 60 秒上限；未在真实暂停状态计时。此前工作区踩坑文档已记录此问题，不是本次游戏更新的新证据。

## 检查范围与限制

- 全部 64 份 PVP Lua 脚本通过 Lua 5.1 编译；语法通过不代表运行行为全部正确。
- 未发现防冻、催眠、减速、影牢核心入口，Boss 掉落、季节 Boss、影人索敌、科技书、队伍地图标记、OB 相机/动作与主要大厅公开接口的明确 API 断裂。
- 泰拉瑞亚之眼规则额外加载本机原版 `terrarium.lua` 的真实闭包做模拟，4 项断言确认 `TimerDone` 中的 `SpawnEyeOfTerror` upvalue 仍可成功替换。
- 上述“未发现”仅表示本轮源码对照未找到具体失效链，不能替代地上/地下、双人联机、暂停、重连、真实 UI 的验证。
