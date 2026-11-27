"""把 web-lite 打成两种可直接分发的产物：

1. dist/dodge-game-lite.zip        —— 标准静态包（zip 根目录就是 index.html），
                                      适用于任何「上传 H5 包 / 指定 index.html 入口」的平台
2. dist/dodge-game-standalone.html —— 单文件版，图片/音频/代码全部内联，双击即玩

用法：python tools/pack_lite.py
"""
import base64
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LITE = ROOT / "web-lite"
DIST = ROOT / "dist"
DIST.mkdir(exist_ok=True)


def b64(path: Path, mime: str) -> str:
    data = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{data}"


# ---------------------------------------------------------------- 1. zip 包
# TapTap / 小游戏平台的要求：zip 解压后「第一层有且仅有一个文件夹」，入口 index.html 在里面；
# 文件夹名只能是英文/数字。所以这里包一层 dodge-game/。
zip_path = DIST / "dodge-game-lite.zip"
if zip_path.exists():
    zip_path.unlink()
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for path in sorted(LITE.rglob("*")):
        if path.is_file():
            zf.write(path, "dodge-game/" + path.relative_to(LITE).as_posix())
print(f"zip  : {zip_path.name}  {zip_path.stat().st_size / 1024:.0f} KB（单层文件夹 dodge-game/）")

# 备用：index.html 直接躺在 zip 根目录的版本（万一平台是按「根目录入口」解析）
flat_path = DIST / "dodge-game-lite-flat.zip"
if flat_path.exists():
    flat_path.unlink()
with zipfile.ZipFile(flat_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for path in sorted(LITE.rglob("*")):
        if path.is_file():
            zf.write(path, path.relative_to(LITE).as_posix())
print(f"备用 : {flat_path.name}  {flat_path.stat().st_size / 1024:.0f} KB（index.html 在根）")

# ---------------------------------------------------------------- 3. 兼容版（经典脚本，不用 ES module）
# 有些平台用 file:// 或特殊容器加载包体，ES module 会被 CORS 拦掉；
# 这里把两个 js 拼成一个普通 <script>，其余资源仍然走相对路径。
core = (LITE / "js" / "core.js").read_text(encoding="utf-8")
game = (LITE / "js" / "game.js").read_text(encoding="utf-8")
classic_dir = DIST / "classic"
if classic_dir.exists():
    for p in sorted(classic_dir.rglob("*"), reverse=True):
        if p.is_file():
            p.unlink()
        elif not any(p.iterdir()):
            p.rmdir()
classic_dir.mkdir(parents=True, exist_ok=True)
(classic_dir / "assets").mkdir(exist_ok=True)
for f in (LITE / "assets").iterdir():
    if f.is_file():
        (classic_dir / "assets" / f.name).write_bytes(f.read_bytes())
(classic_dir / "style.css").write_bytes((LITE / "style.css").read_bytes())

_game = re.sub(r"^import\s*\{[^}]*\}\s*from\s*'\./core\.js';\s*", "", game, flags=re.M | re.S)
_bundle = "(function(){\n'use strict';\n" + re.sub(r"^export\s+", "", core, flags=re.M) + "\n" + _game + "\n})();\n"
(classic_dir / "game.js").write_text(_bundle, encoding="utf-8")

_classic_html = (LITE / "index.html").read_text(encoding="utf-8").replace(
    '<script type="module" src="js/game.js"></script>',
    '<script src="game.js"></script>',
)
(classic_dir / "index.html").write_text(_classic_html, encoding="utf-8")

classic_zip = DIST / "dodge-game-lite-classic.zip"
if classic_zip.exists():
    classic_zip.unlink()
with zipfile.ZipFile(classic_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for path in sorted(classic_dir.rglob("*")):
        if path.is_file():
            zf.write(path, "dodge-game/" + path.relative_to(classic_dir).as_posix())
print(f"兼容 : {classic_zip.name}  {classic_zip.stat().st_size / 1024:.0f} KB（普通 script，不用 module）")

# ---------------------------------------------------------------- 4. 单文件
html = (LITE / "index.html").read_text(encoding="utf-8")
css = (LITE / "style.css").read_text(encoding="utf-8")
core = (LITE / "js" / "core.js").read_text(encoding="utf-8")
game = (LITE / "js" / "game.js").read_text(encoding="utf-8")

# core.js：去掉 export 关键字，变成普通声明
core_inline = re.sub(r"^export\s+", "", core, flags=re.M)

# game.js：去掉 import 语句（core 已经内联在前面）
game_inline = re.sub(
    r"^import\s*\{[^}]*\}\s*from\s*'\./core\.js';\s*",
    "",
    game,
    flags=re.M | re.S,
)

assets = {
    "assets/bg.webp": ("image/webp", LITE / "assets" / "bg.webp"),
    "assets/dragon.png": ("image/png", LITE / "assets" / "dragon.png"),
    "assets/poop1.png": ("image/png", LITE / "assets" / "poop1.png"),
    "assets/poop2.png": ("image/png", LITE / "assets" / "poop2.png"),
    "assets/poop3.png": ("image/png", LITE / "assets" / "poop3.png"),
    "assets/bgm.ogg": ("audio/ogg", LITE / "assets" / "bgm.ogg"),
}

for rel, (mime, path) in assets.items():
    uri = b64(path, mime)
    html = html.replace(rel, uri)
    game_inline = game_inline.replace(rel, uri)

html = re.sub(r'\s*<link rel="preload"[^>]*>', "", html)
html = html.replace('<link rel="stylesheet" href="style.css">', f"<style>\n{css}\n</style>")
html = html.replace(
    '<script type="module" src="js/game.js"></script>',
    f'<script type="module">\n{core_inline}\n{game_inline}\n</script>',
)

single = DIST / "dodge-game-standalone.html"
single.write_text(html, encoding="utf-8")
print(f"单文件: {single.name}  {single.stat().st_size / 1024:.0f} KB")

# 简单自检：确认没有残留的外链
left = [m for m in re.findall(r'(?:src|href)="([^"]+)"', html) if not m.startswith(("data:", "#"))]
print("残留外链:", left if left else "无")
