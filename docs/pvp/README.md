# Bird PVP 文档

这里记录当前 `pvp/` 的实际实现。旧版 `qiaoer`、水月扩展迁移过程和已经删除的补丁不再作为现行设计依据。

## 阅读顺序

1. [总体架构](architecture.md): 入口、加载顺序、`modimport` 与 `require` 边界。
2. [队伍系统](team-system.md): 权威表、预选镜像、玩家状态、上下洞同步。
3. [OB 模式](observer-mode.md): camera shell、权限、地图、移动和组件策略。
4. [UI、聊天与血条](ui-chat.md): 大厅、Tab 计分板、聊天格式和 OB 血条。
5. [管理员与客户端 MOD 策略](admin-security.md): 管理权限、队伍锁和客户端检查。
6. [排错手册](troubleshooting.md): beta 日志、常见崩溃和同步问题。
7. [发布检查](release.md): 保证 `pvp/` 只包含创意工坊需要的文件。

## 模块地图

| 模块 | 入口 | 主要职责 |
| --- | --- | --- |
| 队伍 | [`team.lua`](../../pvp/scripts/src/team.lua) | 权威队伍、玩家状态、聊天、地图标记、队伍圈 |
| OB | [`observer.lua`](../../pvp/scripts/src/observer.lua) | camera shell、观察权限、操作面板、视野 |
| 保护 | [`protection.lua`](../../pvp/scripts/src/protection.lua) | 开局保护和 OB 世界交互隔离 |
| 玩法 | [`gameplay.lua`](../../pvp/scripts/src/gameplay.lua) | 平衡、掉落、开局规则 |
| 世界 | [`world.lua`](../../pvp/scripts/src/world.lua) | 季节 Boss、泰拉瑞亚之眼规则 |
| 大厅 | [`lobby.lua`](../../pvp/scripts/src/lobby.lua) | 预选角色、准备与开局流程 |
| 安全 | [`security.lua`](../../pvp/scripts/src/security.lua) | 客户端 MOD 加载策略 |
| UI | [`ui.lua`](../../pvp/scripts/src/ui.lua) | 大厅按钮、计分板、快捷宣告、血条 |
| RPC | [`core/rpc.lua`](../../pvp/scripts/src/core/rpc.lua) | OB 与管理员操作路由 |

## 战斗设计约束

- PVP 要删除位面伤害（用户于 2026-10-24 确认）。兼容新版战斗接口时须保留这一规则，不能以补全 `spdamage` 参数为由恢复位面伤害。入口绕过的原因与修复见 [759671 兼容性核对](compatibility-759671.md)。

## 维护原则

- 地上世界的队伍表是唯一权威来源，客户端和玩家实体只持有镜像。
- 队伍状态为 `pending` 时，不猜测红队、蓝队或 OB，也不开放聊天和地图可见性。
- 注册 DST Hook 的脚本使用 `modimport`，可复用的状态或动作模块使用 `require`。
- 管理员身份和 OB 身份分开判断，不通过管理员身份隐式获得观察能力。
- `pvp/` 只存放运行时所需内容，维护文档和生成素材放在仓库根目录。

`docs/deobfuscated/` 是工具生成或历史分析区域，不应作为当前架构说明引用。
