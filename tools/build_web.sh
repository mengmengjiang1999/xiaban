#!/bin/bash
set -euo pipefail

game_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$game_root/builds/web"
bash "$game_root/tools/godot.sh" --headless --export-release Web "$game_root/builds/web/index.html"

python3 - "$game_root" <<'PY'
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1])
web = root / 'builds/web'
licenses = web / 'LICENSES.txt'
licenses.write_text(
    'Office Escape / 准点下班 v0.1.0\n'
    'Godot Engine 4.7.2 — MIT license.\n'
    'Godot copyright, license and third-party notices: https://godotengine.org/license/\n'
    'Noto Sans SC Regular — Copyright 2014-2021 Adobe (http://www.adobe.com/), SIL OFL 1.1.\n'
    'The complete font license is included in OFL-NotoSansSC.txt.\n'
    'Models, interface and synthesized audio are created for this project.\n',
    encoding='utf-8',
)
(web / 'OFL-NotoSansSC.txt').write_text((root / 'game/assets/fonts/OFL-NotoSansSC.txt').read_text(), encoding='utf-8')
bundle = root / 'builds/office-escape-level-one-web.zip'
with zipfile.ZipFile(bundle, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(web.rglob('*')):
        if path.is_file() and path.name != '.DS_Store':
            archive.write(path, path.relative_to(web))
with zipfile.ZipFile(bundle) as archive:
    assert 'index.html' in archive.namelist()
    assert archive.testzip() is None
print(f'Web bundle: {bundle} ({bundle.stat().st_size / 1024 / 1024:.2f} MiB)')
PY
