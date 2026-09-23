# 《下班》发布封面

`capture_cover.gd` 在真实 `release.gd` 关卡中摆位取景，使用现有角色、柜子、领导与光照，再叠加标题和副标题。没有外部图片，也不修改生产脚本。画面是明确的宣传摆位，不作为实际键鼠通关或发现判定的证据。

输出固定为 **1260 × 1000**，比例对应 itch.io 的 315:250。使用独立 SubViewport，避免 macOS Retina 缩放改变成品尺寸。

在项目根目录运行编译检查，不开启 GUI：

```bash
bash tools/godot.sh --headless --check-only --script /Users/mmj/Projects/games/xiaban/art/release/capture_cover.gd
```

等待浏览器实机验收结束后，再使用原生 GPU 捕获，避免窗口抢走测试焦点：

```bash
bash tools/godot.sh --resolution 1260x1000 --log-file /tmp/xiaban-release-cover.log --script /Users/mmj/Projects/games/xiaban/art/release/capture_cover.gd -- --output=/Users/mmj/Projects/games/xiaban/art/release/xiaban-cover.png
```

成功日志为 `RELEASE_COVER_OK staged=true width=1260 height=1000`。不传 `--output` 时默认保存为同目录 `xiaban-cover.png`；正式捕获需要原生渲染器，不能用 `--headless` 生成图片。

取景为第一段真实地图：玩家在 `(5.5, 0.05, 30.0)` 蹲姿，工位组长保持原位置和工作姿态，原矮柜居中。关卡推进和检测冻结，正式 HUD 与头顶状态文字隐藏。相机从 `(4.5, 2.5, 33.0)` 看向 `(7.5, 1.0, 29.0)`。脚本不保存设置、不捕获鼠标，也不人为添加危险范围。

捕获后检查：

- 1260 × 1000 原图与缩至 315 × 250 的封面中，“下班”清晰，副标题没有截断。
- 低姿玩家、真实矮柜及至少一位领导均在画面内；柜子不遮住整个人物，标题不压住领导脸部。
- 衣领、工牌、袖口与眼镜没有异常白斑或穿插；墙面、柜顶没有共面频闪痕迹。
- 没有诊断 HUD、鼠标指针、菜单、失败提示或假造视野图形。

构图调整只修改本脚本相机常量、玩家取景位置和标题布局，不修改实际关卡与游戏镜头。封面最终是否采用需以原生捕获后的目检结果为准。
