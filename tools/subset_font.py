"""极简 TrueType(glyf) 子集化：只保留给定字符用到的字形。

为什么需要它：中文字体动辄 8~17 MB，而游戏界面真正用到的字只有几百个。
Godot 没有子集化功能，pip 又装不上 fonttools（这台机器 DNS 不通），所以手写一个。

支持：glyf/loca/cmap(format 4)/hmtx/head/hhea/maxp/OS/2/name/post。
会自动处理复合字形（composite）并重映射字形编号；
可变字体（VF）取默认实例的轮廓、丢掉 gvar/fvar/HVAR 等变化表。

用法：
    python tools/subset_font.py 输入.ttf 输出.ttf
（字符表默认读 tools/_chars.txt）
"""
import struct
import sys
from pathlib import Path


def pad4(b):
    return b + b"\0" * ((4 - len(b) % 4) % 4)


def u16(b, o):
    return struct.unpack_from(">H", b, o)[0]


def i16(b, o):
    return struct.unpack_from(">h", b, o)[0]


def u32(b, o):
    return struct.unpack_from(">I", b, o)[0]


def checksum(data):
    data = pad4(data)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


class Font:
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        self.tables = {}
        num = u16(self.data, 4)
        for i in range(num):
            rec = 12 + i * 16
            tag = self.data[rec:rec + 4].decode("latin1")
            off, ln = u32(self.data, rec + 8), u32(self.data, rec + 12)
            self.tables[tag] = (off, ln)

    def table(self, tag):
        off, ln = self.tables[tag]
        return self.data[off:off + ln]

    def char_map(self):
        cmap = self.table("cmap")
        n = u16(cmap, 2)
        best = None
        for i in range(n):
            rec = 4 + i * 8
            pid, eid, off = u16(cmap, rec), u16(cmap, rec + 2), u32(cmap, rec + 4)
            fmt = u16(cmap, off)
            if fmt == 12:
                best = ("12", off)
                break
            if fmt == 4 and best is None:
                best = ("4", off)
        if best is None:
            raise RuntimeError("没有找到可用的 cmap 子表")
        fmt, off = best
        out = {}
        if fmt == "4":
            segx2 = u16(cmap, off + 6)
            ends = off + 14
            starts = ends + segx2 + 2
            deltas = starts + segx2
            ranges = deltas + segx2
            for s in range(segx2 // 2):
                end = u16(cmap, ends + s * 2)
                start = u16(cmap, starts + s * 2)
                delta = i16(cmap, deltas + s * 2)
                ro = u16(cmap, ranges + s * 2)
                if start == 0xFFFF:
                    continue
                for cp in range(start, end + 1):
                    if ro == 0:
                        gid = (cp + delta) & 0xFFFF
                    else:
                        addr = ranges + s * 2 + ro + (cp - start) * 2
                        gid = u16(cmap, addr)
                        if gid:
                            gid = (gid + delta) & 0xFFFF
                    if gid:
                        out[cp] = gid
        else:
            ngroups = u32(cmap, off + 12)
            for i in range(ngroups):
                g = off + 16 + i * 12
                s, e, gid = u32(cmap, g), u32(cmap, g + 4), u32(cmap, g + 8)
                for cp in range(s, e + 1):
                    out[cp] = gid + (cp - s)
        return out

    def glyph_range(self, gid):
        loca = self.table("loca")
        long_fmt = i16(self.table("head"), 50) == 1
        if long_fmt:
            a, b = u32(loca, gid * 4), u32(loca, gid * 4 + 4)
        else:
            a, b = u16(loca, gid * 2) * 2, u16(loca, gid * 2 + 2) * 2
        return a, b

    def composite_components(self, data):
        """返回 [(组件 gid, gid 字段在 data 中的偏移)]"""
        comps = []
        if len(data) < 10 or i16(data, 0) >= 0:
            return comps
        o = 10
        while True:
            flags = u16(data, o)
            gid = u16(data, o + 2)
            comps.append((gid, o + 2))
            o += 4
            o += 4 if flags & 0x0001 else 2
            if flags & 0x0008:
                o += 2
            elif flags & 0x0040:
                o += 4
            elif flags & 0x0080:
                o += 8
            if not flags & 0x0020:
                break
        return comps


def build_format4(char2gid):
    items = sorted((cp, gid) for cp, gid in char2gid.items() if cp <= 0xFFFF)
    segs = []
    for cp, gid in items:
        if segs and cp == segs[-1][1] + 1 and gid == segs[-1][2] + (cp - segs[-1][0]):
            segs[-1][1] = cp
        else:
            segs.append([cp, cp, gid])
    segs.append([0xFFFF, 0xFFFF, 0])

    seg_count = len(segs)
    segx2 = seg_count * 2
    pow2 = 1
    while pow2 * 2 <= seg_count:
        pow2 *= 2
    search_range = pow2 * 2
    entry_selector = pow2.bit_length() - 1
    range_shift = segx2 - search_range

    ends = b"".join(struct.pack(">H", s[1]) for s in segs)
    starts = b"".join(struct.pack(">H", s[0]) for s in segs)
    deltas = b""
    for s in segs:
        delta = 0 if s[0] == 0xFFFF else (s[2] - s[0]) & 0xFFFF
        deltas += struct.pack(">H", delta)
    ranges = b"\0\0" * seg_count
    # 头部 14 字节 + endCode/startCode/idDelta/idRangeOffset 各 segx2 + 2 字节 reservedPad
    length = 16 + 4 * segx2

    sub = struct.pack(">7H", 4, length, 0, segx2, search_range, entry_selector, range_shift)
    sub += ends + b"\0\0" + starts + deltas + ranges
    return struct.pack(">HH", 0, 1) + struct.pack(">HHI", 3, 1, 12) + sub


def subset_gvar(src_table, order):
    """只保留 order 里这些字形（已重编号）的 gvar 数据，其余原样搬字节。

    gvar 里每个字形的变化数据只引用它自己的点号，所以重编号不影响内容，
    只要把「按字形索引」的那张表重建即可。这样输出的仍然是可变字体，
    可以在 Godot 里用 FontVariation 指定 wght=400 拿到正常字重。
    """
    major, minor, axis_count, shared_count = struct.unpack_from(">HHHH", src_table, 0)
    shared_off, glyph_count, flags = struct.unpack_from(">IHH", src_table, 8)
    data_off = u32(src_table, 16)
    long_fmt = bool(flags & 1)

    offsets = []
    for i in range(glyph_count + 1):
        if long_fmt:
            offsets.append(u32(src_table, 20 + i * 4))
        else:
            offsets.append(u16(src_table, 20 + i * 2) * 2)

    blobs = []
    for gid in order:
        a = data_off + offsets[gid]
        b = data_off + offsets[gid + 1]
        blobs.append(src_table[a:b] if b > a else b"")

    shared_len = shared_count * axis_count * 2
    shared = src_table[shared_off:shared_off + shared_len]

    n = len(blobs)
    offsets_size = 4 * (n + 1)
    shared_offset = 20 + offsets_size
    data_start = shared_offset + shared_len

    new_offsets = []
    acc = 0
    for blob in blobs:
        new_offsets.append(acc)
        acc += len(blob)
    new_offsets.append(acc)

    out = struct.pack(">HHHHIHHI", major, minor, axis_count, shared_count,
                      shared_offset, n, 1, data_start)
    for off in new_offsets:
        out += struct.pack(">I", off)
    out += shared
    out += b"".join(blobs)
    return out


def subset(in_path, out_path, chars):
    f = Font(in_path)
    cmap = f.char_map()
    wanted_cp = {ord(c) for c in chars if ord(c) in cmap}
    gids = {cmap[cp] for cp in wanted_cp}
    gids.add(0)

    work = list(gids)
    while work:
        gid = work.pop()
        a, b = f.glyph_range(gid)
        if b <= a:
            continue
        for comp_gid, _ in f.composite_components(f.table("glyf")[a:b]):
            if comp_gid not in gids:
                gids.add(comp_gid)
                work.append(comp_gid)

    order = [0] + sorted(g for g in gids if g != 0)
    old2new = {old: i for i, old in enumerate(order)}

    hhea = bytearray(f.table("hhea"))
    num_hmetrics = u16(hhea, 34)
    hmtx = f.table("hmtx")
    metrics = []
    last_adv = 0
    for i in range(max(num_hmetrics, max(order) + 1)):
        if i < num_hmetrics:
            adv, lsb = u16(hmtx, i * 4), i16(hmtx, i * 4 + 2)
            last_adv = adv
        else:
            adv = last_adv
            lsb = i16(hmtx, num_hmetrics * 4 + (i - num_hmetrics) * 2)
        metrics.append((adv, lsb))
    new_hmtx = b"".join(struct.pack(">Hh", metrics[g][0], metrics[g][1]) for g in order)

    glyf_src = f.table("glyf")
    glyphs = []
    for gid in order:
        a, b = f.glyph_range(gid)
        data = bytearray(glyf_src[a:b]) if b > a else bytearray()
        if data and i16(data, 0) < 0:
            for comp_gid, off in f.composite_components(bytes(data)):
                struct.pack_into(">H", data, off, old2new[comp_gid])
        glyphs.append(bytes(data))

    glyf = b""
    loca = []
    for g in glyphs:
        loca.append(len(glyf))
        glyf += pad4(g)
    loca.append(len(glyf))

    long_loca = loca[-1] >= 0x20000
    if long_loca:
        loca_data = b"".join(struct.pack(">I", v) for v in loca)
    else:
        loca_data = b"".join(struct.pack(">H", v // 2) for v in loca)

    head = bytearray(f.table("head"))
    struct.pack_into(">H", head, 50, 1 if long_loca else 0)
    struct.pack_into(">I", head, 8, 0)

    struct.pack_into(">H", hhea, 34, len(order))

    maxp = bytearray(f.table("maxp"))
    struct.pack_into(">H", maxp, 4, len(order))
    if len(maxp) >= 32:
        struct.pack_into(">H", maxp, 30, 0)

    post = struct.pack(">I", 0x00030000) + b"\0" * 28

    char2gid = {cp: old2new[cmap[cp]] for cp in wanted_cp}

    out_tables = {
        "head": bytes(head),
        "hhea": bytes(hhea),
        "maxp": bytes(maxp),
        "hmtx": new_hmtx,
        "cmap": build_format4(char2gid),
        "loca": loca_data,
        "glyf": glyf,
        "post": post,
        "OS/2": f.table("OS/2"),
        "name": f.table("name"),
    }
    # 可变字体：保留 fvar / avar / gvar，这样还能用 FontVariation 选字重
    for tag in ("fvar", "avar"):
        if tag in f.tables:
            out_tables[tag] = f.table(tag)
    if "gvar" in f.tables and "fvar" in f.tables:
        out_tables["gvar"] = subset_gvar(f.table("gvar"), order)

    tags = sorted(out_tables)
    num = len(tags)
    pow2 = 1
    while pow2 * 2 <= num:
        pow2 *= 2
    search_range = pow2 * 16
    entry_selector = pow2.bit_length() - 1
    range_shift = num * 16 - search_range
    header = struct.pack(">IHHHH", 0x00010000, num, search_range, entry_selector, range_shift)

    offset = 12 + 16 * num
    directory = b""
    body = b""
    head_offset = None
    for tag in tags:
        data = out_tables[tag]
        if tag == "head":
            head_offset = offset + len(body)
        directory += struct.pack(">4sIII", tag.encode("latin1"), checksum(data),
                                 offset + len(body), len(data))
        body += pad4(data)

    font = bytearray(header + directory + body)
    total = checksum(bytes(font))
    struct.pack_into(">I", font, head_offset + 8, (0xB1B0AFBA - total) & 0xFFFFFFFF)
    Path(out_path).write_bytes(bytes(font))
    return len(order), len(font)


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    src, dst = args[0], args[1]
    chars_path = args[3] if len(args) > 3 else "tools/_chars.txt"
    text = Path(chars_path).read_text(encoding="utf-8")
    n, size = subset(src, dst, text)
    print("glyphs=%d  size=%.1f KB -> %s" % (n, size / 1024, dst))
