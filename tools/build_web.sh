#!/bin/bash
set -euo pipefail

game_root="$(cd "$(dirname "$0")/.." && pwd)"
sample="${1:-release}"
case "$sample" in
  p1) preset="Web"; web_directory="web" ;;
  p2) preset="Web P2"; web_directory="p2-web" ;;
  p3) preset="Web P3"; web_directory="p3-web" ;;
  p4) preset="Web P4"; web_directory="p4-web" ;;
  p4b) preset="Web P4 Full"; web_directory="p4b-web" ;;
  release) preset="Web Release"; web_directory="release-web" ;;
  *) echo 'Usage: bash tools/build_web.sh [p1|p2|p3|p4|p4b|release]' >&2; exit 2 ;;
esac
mkdir -p "$game_root/builds/$web_directory"
bash "$game_root/tools/godot.sh" --headless --export-release "$preset" "$game_root/builds/$web_directory/index.html"

python3 - "$game_root" "$sample" "$web_directory" <<'PY'
from pathlib import Path
import re
import sys
import zipfile

root = Path(sys.argv[1])
sample = sys.argv[2]
web = root / 'builds' / sys.argv[3]
licenses = web / 'LICENSES.txt'
licenses.write_text(
    f'Office Escape / 下班 {sample.upper()}\n'
    'Godot Engine 4.7.2 — MIT license.\n'
    'Godot copyright, license and third-party notices: https://godotengine.org/license/\n'
    'Noto Sans SC Regular — Copyright 2014-2021 Adobe (http://www.adobe.com/), SIL OFL 1.1.\n'
    'The complete font license is included in OFL-NotoSansSC.txt.\n'
    + (f'{sample.upper()} character and animation credits are in CHARACTER-LICENSES.txt.\n' if sample in ('p2', 'p3', 'p4', 'p4b', 'release')
     else 'P1 prototype geometry and interface are created for this project.\n')
    + ('Release character accessories, office textures and procedural audio are original project assets.\n' if sample == 'release' else ''),
    encoding='utf-8',
)
(web / 'OFL-NotoSansSC.txt').write_text((root / 'game/assets/fonts/OFL-NotoSansSC.txt').read_text(), encoding='utf-8')
if sample in ('p2', 'p3', 'p4', 'p4b', 'release'):
    (web / 'CHARACTER-LICENSES.txt').write_text((root / 'game/assets/characters/LICENSES.txt').read_text(), encoding='utf-8')
if sample == 'release':
    version = re.search(r'^config/version="([^"]+)"$', (root / 'game/project.godot').read_text(), re.M).group(1)
    entry = web / 'index.html'
    entry.write_text(entry.read_text().replace('<html lang="en">', '<html lang="zh-CN">')
        .replace('Your browser does not support the canvas tag.', '浏览器无法显示游戏画面，请使用支持 WebGL 2 的电脑浏览器。')
        .replace('Your browser does not support JavaScript.', '请启用 JavaScript 后重新打开游戏。'), encoding='utf-8')
    (web / 'README.txt').write_text(
        f'下班 / Office Escape — {version}\n\n'
        '一个办公室潜行小游戏。穿过三段办公区，走到绿色楼梯口。\n'
        'W/S 前进倒退；A/D 转身；C 蹲起；站姿 Shift+W 冲刺；蹲姿 Space 向前翻滚。\n'
        '方向键或按住右键拖动调整左右、上下视角；滚轮调距；F 回正；Esc 暂停。\n'
        '停止观察后暂留视角，未继续移动则保留；移动触发回正后平滑完成，观察可打断。\n'
        '矮柜后需要蹲下。领导抬头并实际认出你时失败；冲刺声会引他看向声源。\n'
        '暂停菜单可调音量和灵敏度，设置保存在当前浏览器本地。\n\n'
        '运行：通过 HTTP/HTTPS 服务器打开 index.html，不支持双击 file:// 运行。\n'
        'itch.io：上传整个 ZIP，选择 HTML 游戏，保持 index.html 在压缩包根目录。\n'
        '使用键盘与鼠标；没有手机触屏操作。第一次加载需要下载引擎和游戏资源。\n'
        '许可：见 LICENSES.txt、CHARACTER-LICENSES.txt、OFL-NotoSansSC.txt。\n', encoding='utf-8')
bundle = root / f'builds/xiaban-{sample}-web.zip'
with zipfile.ZipFile(bundle, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(web.rglob('*')):
        if path.is_file() and path.name != '.DS_Store':
            archive.write(path, path.relative_to(web))
with zipfile.ZipFile(bundle) as archive:
    assert 'index.html' in archive.namelist()
    assert archive.testzip() is None
print(f'Web bundle: {bundle} ({bundle.stat().st_size / 1024 / 1024:.2f} MiB)')
PY
