# P2 成人角色与动作源文件

2026-09-22。一个 1.75 米成人样板，青绿色短袖、牛仔裤、棕色鞋和短发。外观用于验证人体管线，不代表最终玩家或三位领导的定稿。

## 文件与再构建

- `source/office_adult_base.blend`：MPFB 2.0.17 生成的人体、53 骨骼及六个已穿衣网格；形态、衣物遮蔽、纹理仍可编辑，纹理内嵌。
- `source/quaternius_standard_1_0.glb`：作者免费 Standard-1.0 包中的原始 Godot GLB，含 46 个动作。仅作为重定向输入，不随游戏发布。
- `office_worker.blend`：整理后的角色和六段动作，可直接在 Blender 4.5.9 LTS 打开；NLA 轨道默认静音，检查某动作时取消该轨道静音。
- `../../game/assets/characters/office_worker.glb`：游戏导入产物；旁边的 JSON 记录面数、纹理、动作帧数等实际指标。
- `source/SHA256.json`：两个输入文件的 SHA-256；其余清单记录下载来源、所选素材、原始骨架与 clip。

无需安装 MPFB 即可从已保存的 base 重建。使用 Blender 4.5 LTS，在项目根目录执行：

```bash
blender --background --factory-startup --python tools/build_p2_character.py
bash tools/godot.sh --headless --editor --import --quit
bash tools/godot.sh --headless --fixed-fps 60 --script res://tests/p2_test.gd
bash tools/build_web.sh p2
```

脚本可用 `-- --base=... --animations=... --output=... --blend=...` 覆盖路径。项目本机 Blender 在 `.tools/blender/Blender.app/Contents/MacOS/Blender`；工具本身不纳入仓库。最终 `.blend` 的自动备份 `.blend1` 不是输入。

## 实际处理

首先烘焙成人形态及衣物/鞋底遮蔽，再将主要网格减面到原始的 60%，保留蒙皮权重。最终 **19,069 三角面、53 骨骼、6 个网格、7 个材质、8 张最大 1K 纹理**。皮肤、衣物、鞋和眼睛使用不透明材质，头发与眉毛使用 alpha cutout；不能将全部材质导为 BLEND，否则会发生深度排序错乱。

原衣物遮罩在上臂骨起点后约 5 cm 就结束，而短袖袖口实际位于约 13–14 cm；袖内残留皮肤在抬臂时会穿出衣服。生成脚本在减面前识别左右真实袖口的边界环，投影到各自上臂骨方向，只删除完全处于短袖覆盖区且受该上臂蒙皮控制的身体面。左侧删除 57 面、右侧 63 面，遮罩边界距肩关节分别为 11.67 cm、13.06 cm；袖口下保留至少 12 mm 的皮肤重叠，保留外露上臂、肘部和前臂。这些实测参数写入产物 JSON 的 `sleeve_hidden_body_mask`，源 base 文件不变。

重定向显式映射全部骨骼，校正目标 A 姿态与源 T 姿态的肢体方向。以 60 FPS 烘焙，减少翻滚快速转动在插值帧穿地；不把动作节点连到相机。角色前方统一为 Godot −Z，站立接地顶点高为 25 mm（物理地面为零，可见地毯为 17 mm）；跑步保留自然腾空期。上衣保留 4 mm 的布料间隙，肩袖穿插由上述精确遮蔽修正。代码驱动实际行走位移，动画不提供水平根运动。

| 游戏名 | 源动作 | 秒 | 用途 |
|---|---|---:|---|
| idle | Idle_Loop | 2.500 | 站立呼吸 |
| walk | Walk_Loop | 1.333 | 实际行走，倒退反向播放 |
| run | Sprint_Loop | 0.667 | 原地跑步样板 |
| crouch_idle | Crouch_Idle_Loop | 2.933 | 原地蹲姿 |
| crouch_walk | Crouch_Fwd_Loop | 2.000 | 双足蹲行，不是爬行 |
| roll | Roll | 1.467 | 原地翻滚，首尾混合到蹲姿 |

源 Roll 以站姿结束，本项目修改了前 16% 与后 33% 的衔接，使其从蹲姿进入并回到蹲姿。每帧按实际蒙皮网格校正接地；倒置时根骨垂直偏移较大属于接地校正，不是玩家碰撞体位移。P2 的循环原地展示不等于 P3 的翻滚动作状态、移动距离或低矮碰撞已经完成。

## 来源与许可

人体使用 [MPFB 2.0.17](https://extensions.blender.org/add-ons/mpfb/) 和 [MakeHuman 官方 CC0 系统素材](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html)：male_casualsuit06、shoes01、short01、eyebrow001、low-poly eyes、brown eyes、young_asian_male。仅选择该 CC0 包内容。MPFB ZIP 官方 SHA-256 为 `4f0a879d64a39bf646fbf5f53601ac678855da329d650617dca5737548239a87`。工具代码的 GPL 不适用于这些 CC0 输出；本仓库不打包插件代码。

动作来自 [Quaternius 本人在 Godot 官方资产商店发布的免费 Standard-1.0](https://store.godotengine.org/asset/quaternius/universal-animation-library/)，下载包 SHA-256 为 `18ff1a7215f4852b320203e8aaf02a1578b5c8eef9027fbaedfcedc7b85a3ac2`，原始 GLB SHA-256 为 `1b7bf67866360665426bb99e4c71bd619f19b408453c24e30f0c3071601eee5c`。实际 46 个 clip；未购买 Pro/Source，也未采用账户受限素材。

原始与修改后图形资产均使用 **CC0 1.0 Universal**；允许修改、商用和再分发。完整许可及原作者声明保存在 `licenses/`，游戏发布摘要为 `game/assets/characters/LICENSES.txt`。这些开发源文件位于 `game/` 外，不进入 Web/macOS 包。
