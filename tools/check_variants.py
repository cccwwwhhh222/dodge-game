"""校验 dist/ 下所有分发产物的结构与脚本可用性。"""
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"

variants = [
    ("dodge-game-lite.zip", "module"),
    ("dodge-game-lite-flat.zip", "module-flat"),
    ("dodge-game-lite-classic.zip", "classic"),
]

ok_all = True
for name, kind in variants:
    z = zipfile.ZipFile(DIST / name)
    names = z.namelist()
    tops = {n.split("/")[0] for n in names}
    entry = [n for n in names if n.endswith("index.html")]
    single_top = len(tops) == 1 and entry == [f"{sorted(tops)[0]}/index.html"]
    prefix = "" if kind == "module-flat" else "dodge-game/"

    html = z.read(prefix + "index.html").decode("utf-8")
    uses_module = 'type="module"' in html
    expect_module = kind in ("module", "module-flat")
    ok_html = uses_module == expect_module

    ok_js = True
    if kind == "classic":
        js = z.read(prefix + "game.js").decode("utf-8")
        tmp = ROOT / "_v.js"
        tmp.write_text(js, encoding="utf-8")
        r = subprocess.run(["node", "--check", str(tmp)], capture_output=True, text=True)
        ok_js = r.returncode == 0
        tmp.unlink(missing_ok=True)

    size_kb = (DIST / name).stat().st_size / 1024
    print(f"{name:<32} {size_kb:6.0f} KB  tops={sorted(tops)}  "
          f"单层目录={single_top if kind != 'module-flat' else 'N/A'}  "
          f"module={uses_module}  JS={ok_js}")
    ok_all &= ok_html and ok_js

single = DIST / "dodge-game-standalone.html"
print(f"{single.name:<32} {single.stat().st_size / 1024:6.0f} KB  单文件（内联全部资源）")

print("\n全部通过" if ok_all else "\n有问题")
sys.exit(0 if ok_all else 1)
