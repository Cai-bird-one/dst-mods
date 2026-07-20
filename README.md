# 蔡鸟 Bird 的 DST MOD 开发仓库

## 目录结构

| 路径 | 用途 | 上传创意工坊 |
| --- | --- | --- |
| [`pvp/`](pvp/) |  PVP MOD 运行源码、资源、配置 | 是 |
| [`docs/`](docs/) | 按 MOD 分类的中文维护文档 | 否 |
| [`tools/pvp/`](tools/pvp/) | 反混淆和资源维护工具 | 否 |
| `.gitignore`、`.gitattributes` | 仓库规则 | 否 |

不要把文档、原始素材、调试脚本或备份放进 `pvp/`。发布时应只选择 `pvp/` 目录。

## 文档入口

| MOD | 源码 | 文档 |
| --- | --- | --- |
| 【月落繁星】饥荒pvp专用mod | [`pvp/`](pvp/) | [`docs/pvp/`](docs/pvp/) |

PVP 维护入口:

- [文档导航](docs/pvp/README.md)
- [总体架构](docs/pvp/architecture.md)
- [队伍系统](docs/pvp/team-system.md)
- [排错手册](docs/pvp/troubleshooting.md)

新增其他 MOD 文档时，使用 `docs/<mod目录名>/README.md` 作为入口，并在上表登记。

## PVP MOD 本次更新摘要

本次改动集中在选人/开局流程与大厅 UI，文件均位于 `pvp/scripts/` 并带有 `[PATCH]` 注释。

### 准备与开局
- 开局条件强制为 **全员准备**（`ADMIN_MODE = "ALL"`），管理员点准备也不会立刻开局。
- 等待区 / OB 玩家点准备 **无效**，客户端对其隐藏准备按钮，服务端直接忽略该命令。
- 修复点准备时因调用未定义函数 `UpdateReadyCountNet()` 导致的崩溃。
- 修复原版 waitingforplayers 在人未满时弹“强制开始”确认窗，导致准备不生效的问题。
- 修复准备按钮因手柄检测被隐藏的问题，确保红蓝队玩家可见。

### 大厅 UI
- 选人/等待界面的标题“正在等待其他玩家 (x/y)”移到红队与蓝队中间显示。
- 隐藏选人界面右下角“地形预览！”按钮及原版地形预览窗口。

### 其他
- 恢复开局自动暂停逻辑。
- 移除实验性的聊天框 `/ready` 准备功能。

> 注意：发布时只上传 `pvp/` 目录；调试、备份和差异说明不要放进该目录。
