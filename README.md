# office-escape

《准点下班》：一个可玩的 3D 单人办公室潜行关卡。控制程序员绕开三位领导，穿过办公室，抵达楼梯出口。

第一关 v0.1 已实现：移动与跑步、碰撞、可见视野及遮挡、警戒与追赶、巡逻返回、成功失败、暂停重试、中文界面、基础动作及合成音效。使用 Godot 4.7.2 / GDScript / Compatibility。

2026-09-20 调整下一阶段方向：右肩过肩第三人称、成人比例人形、蹲走／冲刺／蹲姿翻滚；仍只做第一关。目前仅完成新方向规划，游戏代码与试玩包仍为斜俯视 v0.1。

第一阶段保存于 [`2D-version`](https://github.com/mengmengjiang1999/xiaban/tree/2D-version) 分支（`d0233cd`）；该名称沿用用户要求，游戏本身仍为 3D。`main` 保留并记录后续计划。源码仓库：[mengmengjiang1999/xiaban](https://github.com/mengmengjiang1999/xiaban)。

![第一阶段斜俯视版本实机画面](docs/images/level-one-game.png)

当前可玩版本：WASD / 方向键移动，Shift 跑步，Esc 暂停；结算后按 R 重试。观察通关的自动输入回放约 30 秒，首次游玩时长尚未统计。新计划中的鼠标转向、蹲伏和翻滚尚未实现。

开发环境为 Mac，当前发布目标为 itch.io 的电脑浏览器版本；Steam 为后续可能路线。

文档入口：

- [开发计划](开发计划.md)：当前过肩第三人称方案、制作顺序、动作规则与 P0～P6 验收。
- [人物模型与动画资源选型](docs/人物模型与动画资源选型.md)：可复用人形、动画、许可及样板验证方案。
- [第一阶段开发计划归档](开发计划-v0.1归档.md)：斜俯视 v0.1 的 M0～M6 原计划。
- [第一关试玩说明](docs/第一关试玩说明.md)：给玩家的规则、操作和启动方法。
- [第一关测试记录](docs/第一关测试记录.md)：实际通过项、回放结果与验证边界。
- [itch 页面文案](docs/itch页面文案.md)：可用的介绍文案和上传材料。
- [素材授权](docs/素材授权.md)：字体、模型与音效来源。
- [项目设定](项目设定.md)：已确认的玩法、范围、发布方向及待定事项。
- [第一关设计](docs/第一关设计.md)：第一阶段地图底稿，供新版本复用路线与三段挑战。
- [第一关任务清单](docs/第一关任务清单.md)：第一阶段 D0～M6 的执行与验收记录。
- [itch.io 发布与 Steam 迁移](docs/itch发布与Steam迁移.md)：当前 Web 交付方式、未来桌面适配、平台手续与官方来源。
- [运行与导出](docs/运行与导出.md)：打开工程、启动本地试玩、重新打包。
- [M0 测试记录](docs/M0测试记录.md)：通过项、截图和仍需补测的范围。

本地试玩：在本目录运行 `python3 tools/serve_web.py`，再打开 <http://127.0.0.1:8765/>。

工程入口：`game/project.godot`。Web 上传包：`builds/office-escape-level-one-web.zip`（约 17 MiB）。没有创建 itch 页面或公开发布；Safari、Windows 和外部玩家试玩待验证。

回归：`bash tools/godot.sh --headless --script res://tests/level_test.gd`。
完整输入回放：`bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/playthrough.gd`。
