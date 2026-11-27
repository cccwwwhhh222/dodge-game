"""校验打包产物：单文件版的内联脚本语法、外链残留、zip 结构。"""
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
single = ROOT / "dist" / "dodge-game-standalone.html"
zp = ROOT / "dist" / "dodge-game-lite.zip"

html = single.read_text(encoding="utf-8")
m = re.search(r'<script type="module">(.*?)</script>', html, re.S)
js = m.group(1)
print(f"内联脚本: {len(js)} 字符")
print(f"残留 import: {'import ' in js[:4000]}")
print(f"data URI 数量: {html.count('data:')}")

tmp = ROOT / "_inl.mjs"
tmp.write_text(js, encoding="utf-8")
r = subprocess.run(["node", "--check", str(tmp)], capture_output=True, text=True)
print("单文件 JS 语法:", "OK" if r.returncode == 0 else "FAIL\n" + r.stderr[:400])
tmp.unlink(missing_ok=True)

links = [u for u in re.findall(r'(?:src|href)="([^"]+)"', html) if not u.startswith(("data:", "#"))]
print("残留外链:", links if links else "无")

z = zipfile.ZipFile(zp)
names = z.namelist()
tops = {n.split("/")[0] for n in names}
entries = [n for n in names if n.endswith("index.html")]
print("zip 顶层:", sorted(tops))
print("入口文件:", entries)
print(f"zip 文件数: {len(names)}，解压后 {sum(z.getinfo(n).file_size for n in names)/1024:.0f} KB")
ok_zip = len(tops) == 1 and entries == [f"{sorted(tops)[0]}/index.html"]
print("结构符合平台要求（单层文件夹 + 入口在其中）:", ok_zip)
sys.exit(0 if r.returncode == 0 and not links and ok_zip else 1)
