#!/usr/bin/env python3
"""真机截图分析：判定当前页面 + 扫描文字墨迹块。

用法：
  python tools/screen-analyze.py dist/device.bmp            # 判定页面 + 列出文字块
  python tools/screen-analyze.py dist/device.bmp --boxes    # 只列文字块
  python tools/screen-analyze.py dist/device.bmp --art 0 240 0 240   # 指定区域字符画

为什么不用"单区域亮度计数"：助手待机页的卡通形象是一大块蓝色像素，会被误判成刻度盘/播放器页，
所以判定必须包含"结构性特征"（面板边框横线）与"多区域同时满足"。
"""
import struct, sys, os

def load(path):
    f = open(path, 'rb').read()
    off = struct.unpack_from('<I', f, 10)[0]
    w, h = struct.unpack_from('<ii', f, 18)
    bpp = struct.unpack_from('<H', f, 28)[0]
    rb = ((w * bpp // 8) + 3) // 4 * 4
    def v(x, y):
        q = off + (h - 1 - y) * rb + x * (bpp // 8)
        return max(f[q], f[q + 1], f[q + 2])
    return w, h, v

def count(v, y0, y1, x0, x1, th):
    return sum(1 for y in range(y0, y1) for x in range(x0, x1) if v(x, y) > th)

def row_run(v, y, x0, x1, th):
    return sum(1 for x in range(x0, x1) if v(x, y) > th)

def classify(v, w, h):
    """返回 (页面名, 特征字典)。特征全部来自实测几何（见 docs/development/radio-native-plan.md）。"""
    top    = count(v, 2, 20, 8, 90, 40)        # 顶栏 CH 文字（琥珀）
    row78  = row_run(v, 78, 30, 200, 12)       # 刻度盘面板上边框整行
    dial   = count(v, 84, 126, 30, 200, 12)    # 刻度盘面板内部
    meter  = count(v, 142, 180, 22, 218, 12)   # 电平条面板内部
    hint   = count(v, 214, 236, 8, 232, 30)    # 底部提示行文字
    f = dict(top=top, row78=row78, dial=dial, meter=meter, hint=hint)
    if top > 20 and row78 > 50 and meter > 200:
        return 'player', f
    if row78 > 50 and dial > 300 and meter < 200:
        return 'menu-or-list', f
    return 'unknown', f

def boxes(v, w, h, th=90):
    """逐行找亮像素段，合并为文字块（x0,y0,x1,y1）。"""
    blocks = []
    prev = []
    for y in range(h):
        xs = [x for x in range(w) if v(x, y) > th]
        segs = []
        for x in xs:
            if segs and x - segs[-1][1] <= 6:
                segs[-1][1] = x
            else:
                segs.append([x, x])
        for s in segs:
            hit = None
            for p in prev:
                if not (s[1] < p[0] - 6 or s[0] > p[1] + 6):
                    hit = p; break
            if hit:
                hit[0] = min(hit[0], s[0]); hit[1] = max(hit[1], s[1]); hit[3] = y
            else:
                blocks.append([s[0], y, s[1], y]); prev.append(blocks[-1])
        prev = [p for p in prev if p[3] == y]
    return [b for b in blocks if b[2] - b[0] >= 5]

def art(v, y0, y1, x0, x1, step=2):
    for y in range(y0, y1, step):
        line = ''
        for x in range(x0, x1, step):
            m = max(v(x, y), v(min(x + 1, x1 - 1), y))
            line += '#' if m > 120 else ('+' if m > 60 else ('.' if m > 25 else ' '))
        print('%3d|%s' % (y, line))

def main():
    if len(sys.argv) < 2:
        print(__doc__); return
    path = sys.argv[1]
    if not os.path.exists(path):
        print('文件不存在：%s' % path); return
    w, h, v = load(path)
    if '--art' in sys.argv:
        i = sys.argv.index('--art')
        y0, y1, x0, x1 = (int(a) for a in sys.argv[i + 1:i + 5])
        art(v, y0, y1, x0, x1); return
    page, f = classify(v, w, h)
    print('PAGE=%s  %s' % (page, ' '.join('%s=%d' % kv for kv in f.items())))
    if page == 'unknown' or '--boxes' in sys.argv:
        print('文字块（x0..x1, y0..y1, 尺寸）：')
        for b in boxes(v, w, h):
            print('  x=%3d..%3d y=%3d..%3d  (%dx%d)' % (b[0], b[2], b[1], b[3], b[2] - b[0] + 1, b[3] - b[1] + 1))
    return 0

if __name__ == '__main__':
    sys.exit(main())
