"""从 _poop_src.jpg 里把三个表情便便抠出来，去掉白底，输出透明 PNG。

思路：
1. 白色背景 = RGB 三通道都很高；但「白色眼球」也是白的，不能直接抠掉。
2. 所以只删掉「与图片边框连通的白」——眼球被深色描边包住，是内部白，会保留。
3. 从三个种子点做 flood fill，各自得到一块前景，取连通块 bbox（这样水印、噪点不会撑大裁切框）。
4. 裁切后按预乘 alpha 缩放，避免边缘出现白边光晕。
"""
import numpy as np
from PIL import Image

SRC = "assets/_poop_src.jpg"
OUT_DIR = "assets"
SIZE = 256

im = Image.open(SRC).convert("RGB")
arr = np.asarray(im).astype(np.int16)
h, w, _ = arr.shape
mn = arr.min(axis=2)
print(f"source: {w}x{h}")

# 1) 白底候选（背景实测 min 通道中位数 249）
white = mn >= 244

# 2) 只保留与边框连通的白色 → bg
bg = np.zeros_like(white)
bg[0, :] = white[0, :]
bg[-1, :] = white[-1, :]
bg[:, 0] = white[:, 0]
bg[:, -1] = white[:, -1]
for i in range(2000):
    grow = bg.copy()
    grow[1:, :] |= bg[:-1, :]
    grow[:-1, :] |= bg[1:, :]
    grow[:, 1:] |= bg[:, :-1]
    grow[:, :-1] |= bg[:, 1:]
    grow &= white
    if grow.sum() == bg.sum():
        print(f"bg flood fill converged after {i} iters, {int(bg.sum())} px")
        break
    bg = grow

fg_all = ~bg

# 3) 三个种子点（分别落在三张脸上）
seeds = {
    "enemy_happy": (330, 380),
    "enemy_shocked": (940, 380),
    "enemy_angry": (630, 900),
}

for name, (sx, sy) in seeds.items():
    if not fg_all[sy, sx]:
        # 种子落在背景上就向四周找一个前景像素
        for r in range(1, 60):
            found = False
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if 0 <= sy + dy < h and 0 <= sx + dx < w and fg_all[sy + dy, sx + dx]:
                        sx, sy = sx + dx, sy + dy
                        found = True
                        break
                if found:
                    break
            if found:
                break

    mask = np.zeros_like(fg_all)
    mask[sy, sx] = True
    for i in range(2000):
        grow = mask.copy()
        grow[1:, :] |= mask[:-1, :]
        grow[:-1, :] |= mask[1:, :]
        grow[:, 1:] |= mask[:, :-1]
        grow[:, :-1] |= mask[:, 1:]
        grow &= fg_all
        if grow.sum() == mask.sum():
            break
        mask = grow

    ys, xs = np.where(mask)
    bx0, bx1, by0, by1 = xs.min(), xs.max(), ys.min(), ys.max()
    pad = 4
    bx0, by0 = max(0, bx0 - pad), max(0, by0 - pad)
    bx1, by1 = min(w - 1, bx1 + pad), min(h - 1, by1 + pad)

    crop = im.crop((bx0, by0, bx1 + 1, by1 + 1))
    alpha = np.where(bg[by0:by1 + 1, bx0:bx1 + 1], 0, 255).astype(np.uint8)
    rgba = crop.convert("RGBA")
    rgba.putalpha(Image.fromarray(alpha, "L"))

    small = rgba.convert("RGBa").resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    out = f"{OUT_DIR}/{name}.png"
    small.save(out)
    print(f"{name}: comp={int(mask.sum())}px bbox=({bx0},{by0},{bx1},{by1}) "
          f"crop={(bx1 - bx0 + 1, by1 - by0 + 1)} -> {out}")
