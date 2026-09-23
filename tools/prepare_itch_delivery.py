"""Collect the already verified build and authored publication materials."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "builds/itch-upload"
OUTPUT.mkdir(parents=True, exist_ok=True)
(OUTPUT / "screenshots").mkdir(exist_ok=True)
manifest = json.loads((ROOT / "builds/release-manifest.json").read_text())
web = ROOT / "builds/xiaban-release-web.zip"
assert hashlib.sha256(web.read_bytes()).hexdigest() == manifest["bundles"][web.name]["sha256"]
shutil.copy2(web, OUTPUT / web.name)
shutil.copy2(ROOT / "art/release/xiaban-cover.png", OUTPUT / "cover.png")
for index, name in enumerate(["release-team-lead", "release-observe", "release-action", "release-manager-observe", "release-win"], 1):
    shutil.copy2(ROOT / f"docs/images/{name}.png", OUTPUT / f"screenshots/{index:02d}-{name}.png")
page = (ROOT / "docs/itch页面文案.md").read_text()
copy = page.split("## 标题\n", 1)[1].split("## 发布准备备注", 1)[0].strip()
(OUTPUT / "页面正文.md").write_text(copy + "\n")
shutil.copy2(ROOT / "builds/release-web/README.txt", OUTPUT / "试玩操作.txt")
(OUTPUT / "上传说明.md").write_text(
    "# 《下班》1.0.0 上传材料\n\n"
    "这份目录尚未上传。选择用户自己的 itch.io 账号和项目，先保持草稿页面，完成托管验收后再公开。\n\n"
    "1. 类型选择 HTML Game，上传 `xiaban-release-web.zip`，将它标为浏览器中运行的文件。\n"
    "2. 使用 `cover.png`（1260×1000）和 `screenshots/` 中的五张真实场景截图。\n"
    "3. 页面标题、简介、正文见 `页面正文.md`。保持免费、不配置收款，不勾选 Mobile Friendly。\n"
    "4. 采用点击加载，初始画布1152×720；测试网站实际全屏和鼠标捕获权限。\n"
    "5. 在真实托管页面检查加载、开始、C/Space、暂停继续、失焦、三位领导失败、通关与音量保存。\n\n"
    "已完成本地 Chrome 67项与引擎92项验收；Safari只有真实操作烟测，不宣称完整整关兼容。\n"
    "macOS开发包另在 `builds/xiaban-macos.zip`，未公证，未默认加入网页上传内容。\n\n"
    "封面是使用真实游戏资产的宣传摆位；画廊第一张为正式原生摆位，其余四张来自真实 Chrome 键鼠整关路线。\n\n"
    "官方上传说明：https://itch.io/docs/creators/html5\n"
)
files = {}
for file in sorted(OUTPUT.rglob("*")):
    if file.is_file() and file.name != "材料清单.json":
        files[str(file.relative_to(OUTPUT))] = {"bytes": file.stat().st_size, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
(OUTPUT / "材料清单.json").write_text(json.dumps({"version": manifest["version"], "uploaded": False, "files": files}, ensure_ascii=False, indent=2) + "\n")
print(f"Prepared {len(files)} files in {OUTPUT}")
