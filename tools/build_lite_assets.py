"""把 Godot 工程里的美术/音频转成网页轻量版所需的资源。

- 背景：WebP（无透明通道，画质 80）  —— Pillow 这个版本没编 webp，走 ffmpeg
- 精灵：PNG（保留 alpha，缩到实际显示尺寸）
- 音乐：沿用 ogg（懒加载，不阻塞首屏）

用法：python tools/build_lite_assets.py
"""
import shutil
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent          # godot_dodge/
OUT = Path(__file__).resolve().parents[1] / "web-lite" / "assets"
FFMPEG = Path(r"C:\Users\12841\anaconda3\lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win64-v4.2.2.exe")

OUT.mkdir(parents=True, exist_ok=True)
total = 0


def report(name, size):
    global total
    total += size
    print(f"{name:<28} {size / 1024:7.1f} KB")


def ffmpeg(*args):
    subprocess.run([str(FFMPEG), "-y", "-hide_banner", "-loglevel", "error", *args], check=True)


# 1) 背景：先缩到 720x963 存 PNG，再让 ffmpeg 转 WebP
bg_src = ROOT / "assets" / "bg_farm.png"
bg_tmp = OUT / "_bg_tmp.png"
Image.open(bg_src).convert("RGB").resize((720, 963), Image.LANCZOS).save(bg_tmp, optimize=True)
bg_webp = OUT / "bg.webp"
ffmpeg("-i", str(bg_tmp), "-c:v", "libwebp", "-quality", "80", "-compression_level", "6", str(bg_webp))
bg_tmp.unlink()
report("bg.webp", bg_webp.stat().st_size)

# 2) 精灵：缩到显示尺寸的 2 倍（适配高分屏），保留 alpha
sprites = [
    ("dragon.png", "dragon.png", (300, 298)),
    ("enemy_happy.png", "poop1.png", (180, 180)),
    ("enemy_shocked.png", "poop2.png", (180, 180)),
    ("enemy_angry.png", "poop3.png", (180, 180)),
]
for src_name, dst_name, size in sprites:
    im = Image.open(ROOT / "assets" / src_name).convert("RGBA").resize(size, Image.LANCZOS)
    dst = OUT / dst_name
    im.save(dst, optimize=True)
    report(dst_name, dst.stat().st_size)

# 3) 音频：直接复制（懒加载）
bgm_src = ROOT / "assets" / "audio" / "bgm.ogg"
bgm_dst = OUT / "bgm.ogg"
shutil.copyfile(bgm_src, bgm_dst)
report("bgm.ogg（懒加载）", bgm_dst.stat().st_size)

print("-" * 40)
print(f"首屏关键路径（图+代码）≈ {(total - bgm_dst.stat().st_size) / 1024:.0f} KB")
print(f"全部资源合计           ≈ {total / 1024:.0f} KB")
