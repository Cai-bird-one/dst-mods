# 发布检查

## 发布边界

创意工坊只上传 [`pvp/`](../../pvp/) 目录。以下内容不属于发布包:

- `docs/`
- `tools/`
- Git 元数据
- 下载文件、临时 ZIP、日志和备份
- 其他本地 MOD 目录

当前动画源包位于 [`tools/pvp/generated_assets/`](../../tools/pvp/generated_assets/)，发布用动画包位于 [`pvp/anim/`](../../pvp/anim/)。

## 现有创意工坊条目与上传方式

- PVP 条目为 [`3752181777`](https://steamcommunity.com/sharedfiles/filedetails/?id=3752181777)，名称为 `【月落繁星】饥荒pvp专用mod（测试版）`。更新此条目时选择 Edit，不新建条目。
- 本机已安装官方 `Don't Starve Mod Tools/ModUploader.exe`，可使用已登录的 Steam 会话上传。
- 官方上传器保存的目录对应关系在 `HKCU\Software\Klei\Don't Starve Mod Uploader\MRU\3752181777` 的 `DataFolder`；当前指向本工作区的 `pvp/`。每次上传仍须核对条目链接和实际目录。
- 先递增 `pvp/modinfo.lua` 的版本，再在更新对话框启用 `Update Data`，填写 Patch Notes。官方工具会从模组信息读取版本标签；不需改封面或工坊说明时保持对应更新选项关闭，不启用 `Upload redundant files`。
- 官方回执在 `%LOCALAPPDATA%\Don't Starve Mod Uploader\ModUploader.log`。先确认本次 `CopyToTempDir` 的源目录，再确认目标 ID 的 `EResult 1` 与 `Publish complete`；最后 Refresh，核对服务器返回的新版本标签。单纯点击 Publish 不算上传完成。

2026-10-24 已按此流程发布 `1.0beta.27`（修复提交 `f7cf456`）。上传回执为 `EResult 1, 00000000dfa5c011`，其中十六进制 ID 对应 `3752181777`；刷新列表确认 `version:1.0beta.27`。这证明工坊接受了更新，未进行独立重新下载或真实联机验证。

## 1.0beta.28 修复内容

- 恢复新版普攻、范围攻击、反伤及伤害重定向的位面伤害屏蔽，同时恢复受击血条触发。
- 修复第一天旋风杖可对非玩家目标施法绕过保护，追溯已有旋风的玩家来源。
- 适配 WX-78 三栏模块名称、数量、卸载复用及动态电量上限。
- 透传聊天静默参数，保留队聊过滤。
- 修复开局等待 90/120 秒错误回退为 30 秒。

验证：位面 527、第一天保护 214、旋风杖 166、聊天 46、WX-78 44 项 Lua 5.1 断言通过；等待时长配置 14 个检查通过，全部 64 份 Lua 脚本通过编译。上述为本机原版 Lua 与引擎桩的离线验证，未做真实客户端联机验证。详细证据见 [兼容性核对](compatibility-759671.md)。

2026-10-24 已发布 `1.0beta.28`，对应修复提交 `b0b37e0`，已推送至 `origin/main`。官方上传器于本地时间 18:33:13 返回 `EResult 1, 00000000dfa5c011` 和 `Publish complete`；18:33:38 刷新确认现有条目 `3752181777` 返回 `version:1.0beta.28`。上传源目录核对为本工作区的 `pvp/`，未上传文档、测试或其他模组；未做独立重新下载验证。

## `pvp/` 允许内容

- `modinfo.lua`、`modmain.lua`、`modworldgenmain.lua`
- `modicon.tex`、`modicon.xml`、`mod.manifest`
- `anim/`、`announcestrings/`
- `scripts/` 下的运行源码、组件、prefab 和 widget

不要在 `pvp/` 中加入:

- `docs/`
- `tools/`
- `backup/`、`temp/`、`downloads/`
- 原始 PSD、工程文件、解包后的动画源码
- 客户端和服务端日志

## 提交前检查

1. 查看 `git status --short`，确认没有误加入其他本地 MOD。
2. 查看 `git diff --check`，排除空白错误。
3. 搜索旧命名 `qiaoer`，确认不是兼容需求。
4. 搜索 `pvp/docs` 和 `pvp/tools`，结果应为空。
5. 检查 `modinfo.lua` 版本和配置默认值。
6. 使用包含 `beta` 的版本完成地上、地下、重连和大厅测试。
7. 发布前确认动画 bank、prefab 名和资源 ZIP 一致。

## 最小回归场景

- 新存档进入大厅，默认等待，手动选红蓝和 OB。
- 等待人员分队与全部人员分队，人数保持平衡。
- 统一锁阻止普通玩家自选，但管理员和自动分队可修改。
- 游戏开始时有人未选角色，不进入其生成流程且客户端不崩溃。
- 红蓝玩家上下洞、死亡、重连后队伍不变。
- pending 阶段不显示敌方地图头像，不发送队伍聊天。
- OB 上下洞后仍有移动、地图、视野和血条观察能力。
- 普通客户端 MOD 被静默禁用，高优先级客户端 MOD 被拒绝。
