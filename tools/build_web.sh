#!/bin/bash
set -euo pipefail

game_root="$(cd "$(dirname "$0")/.." && pwd)"
sample="${1:-p1}"
case "$sample" in
  p1) preset="Web"; web_directory="web" ;;
  p2) preset="Web P2"; web_directory="p2-web" ;;
  *) echo 'Usage: bash tools/build_web.sh [p1|p2]' >&2; exit 2 ;;
esac
mkdir -p "$game_root/builds/$web_directory"
bash "$game_root/tools/godot.sh" --headless --export-release "$preset" "$game_root/builds/$web_directory/index.html"

python3 - "$game_root" "$sample" "$web_directory" <<'PY'
from pathlib import Path
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
    + ('P2 character and animation credits are in CHARACTER-LICENSES.txt.\n' if sample == 'p2'
     else 'P1 prototype geometry and interface are created for this project.\n'),
    encoding='utf-8',
)
(web / 'OFL-NotoSansSC.txt').write_text((root / 'game/assets/fonts/OFL-NotoSansSC.txt').read_text(), encoding='utf-8')
if sample == 'p2':
    (web / 'CHARACTER-LICENSES.txt').write_text((root / 'game/assets/characters/LICENSES.txt').read_text(), encoding='utf-8')
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
