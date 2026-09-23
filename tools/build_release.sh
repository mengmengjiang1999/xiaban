#!/bin/bash
set -euo pipefail
release_root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$release_root/tools/godot.sh" --headless --editor --quit
bash "$release_root/tools/build_web.sh" release
mkdir -p "$release_root/builds/macos"
bash "$release_root/tools/godot.sh" --headless --export-release 'macOS Release' "$release_root/builds/macos/Xiaban.app"
codesign --verify --deep --strict "$release_root/builds/macos/Xiaban.app"
python3 - "$release_root" <<'PY'
from pathlib import Path
import hashlib
import json
import re
import sys
import zipfile

root = Path(sys.argv[1])
version = re.search(r'^config/version="([^"]+)"$', (root / 'game/project.godot').read_text(), re.M).group(1)
web = root / 'builds/release-web'
app = root / 'builds/macos/Xiaban.app'
web_pck = web / 'index.pck'
native_pcks = list(app.rglob('*.pck'))
assert len(native_pcks) == 1
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert digest(web_pck) == digest(native_pcks[0]), 'Web and native game contents differ'
native_zip = root / 'builds/xiaban-macos.zip'
with zipfile.ZipFile(native_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file() and path.name != '.DS_Store':
            archive.write(path, path.relative_to(app.parent))
    for name in ['LICENSES.txt', 'CHARACTER-LICENSES.txt', 'OFL-NotoSansSC.txt']:
        archive.write(web / name, name)
    archive.writestr('README.txt', f'下班 / Office Escape — {version}\n\n解压后运行 Xiaban.app。\n'
        'W/S 前进倒退，A/D 转身，C 蹲起，站姿 Shift+W 冲刺，蹲姿 Space 翻滚。\n'
        '方向键或按住右键拖动调整左右、上下视角，滚轮调距，F 回正，Esc 暂停。\n'
        '停止观察后暂留视角，未继续移动则保留；移动触发回正后平滑完成，观察可打断。\n'
        '这是本地开发构建，采用 ad-hoc 签名，未做 Apple 公证或商店分发。\n'
        '兼容性与本轮实测范围见项目 docs/发布前稳定性测试记录.md。\n')
with zipfile.ZipFile(native_zip) as archive:
    assert archive.testzip() is None
manifest = {
    'version': version,
    'scene': 'res://scenes/release.tscn',
    'pck_sha256': digest(web_pck),
    'pck_bytes': web_pck.stat().st_size,
    'bundles': {path.name: {'bytes': path.stat().st_size, 'sha256': digest(path)}
                for path in [root / 'builds/xiaban-release-web.zip', native_zip]},
    'native_signing': 'ad-hoc; codesign strict verified; not notarized',
    'validation_note': 'Packaging checks only. Gameplay and browser results are recorded separately.'
}
(root / 'builds/release-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(manifest, ensure_ascii=False, indent=2))
PY
