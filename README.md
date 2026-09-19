# office-escape

《准点下班》：一个可玩的 3D 单人办公室潜行关卡。控制程序员绕开三位领导，穿过办公室，抵达楼梯出口。

第一关 v0.1 已实现：移动与跑步、碰撞、可见视野及遮挡、警戒与追赶、巡逻返回、成功失败、暂停重试、中文界面、基础动作及合成音效。使用 Godot 4.7.2 / GDScript / Compatibility。

第一阶段到此保留为可玩原型，后续根据试玩反馈再安排开发。源码仓库：[mengmengjiang1999/xiaban](https://github.com/mengmengjiang1999/xiaban)。

![第一关实机画面](docs/images/level-one-game.png)

WASD / 方向键移动，Shift 跑步，Esc 暂停；结算后按 R 重试。观察通关的自动输入回放约 30 秒，首次游玩时长尚未统计。

开发环境为 Mac，当前发布目标为 itch.io 的电脑浏览器版本；Steam 为后续可能路线。

文档入口：

- [第一关试玩说明](docs/第一关试玩说明.md)：给玩家的规则、操作和启动方法。
- [第一关测试记录](docs/第一关测试记录.md)：实际通过项、回放结果与验证边界。
- [itch 页面文案](docs/itch页面文案.md)：可用的介绍文案和上传材料。
- [素材授权](docs/素材授权.md)：字体、模型与音效来源。
- [项目设定](项目设定.md)：已确认的玩法、范围、发布方向及待定事项。
- [开发计划](开发计划.md)：模块、M0～M6 里程碑、学习重点及验收标准。
- [第一关设计](docs/第一关设计.md)：俯视布局初稿、三段挑战、观察点、巡逻与灰盒参考。
- [第一关任务清单](docs/第一关任务清单.md)：按 D0～M6 执行的任务、依赖与验收步骤。
- [itch.io 发布与 Steam 迁移](docs/itch发布与Steam迁移.md)：当前 Web 交付方式、未来桌面适配、平台手续与官方来源。
- [运行与导出](docs/运行与导出.md)：打开工程、启动本地试玩、重新打包。
- [M0 测试记录](docs/M0测试记录.md)：通过项、截图和仍需补测的范围。

本地试玩：在本目录运行 `python3 tools/serve_web.py`，再打开 <http://127.0.0.1:8765/>。

工程入口：`game/project.godot`。Web 上传包：`builds/office-escape-level-one-web.zip`（约 17 MiB）。没有创建 itch 页面或公开发布；Safari、Windows 和外部玩家试玩待验证。

回归：`bash tools/godot.sh --headless --script res://tests/level_test.gd`。
完整输入回放：`bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/playthrough.gd`。
