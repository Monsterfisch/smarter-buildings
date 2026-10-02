"""The Repair button's places per panel, its cost text and the gold part, and the layer the
game's own cost text goes on - on both exes."""
import struct
from test_behaviour import W, check, find_menu, FAILS, COUNT
from harness import MASK, SENTINEL


def run(ext):
    print('== ' + ('Extreme' if ext else 'Crusader'))
    w = W(ext); H = w.H; E = w.E
    start, status = find_menu(w)
    text_item = start
    while not (E.u32(text_item) == 3 and E.i32(text_item + 4) == 20 and E.i32(text_item + 8) == 415):
        text_item += 0x50
    render = H.u32(status + 0x1C)
    text = H.u32(text_item + 0x1C)
    orig_render, orig_text = E.u32(status + 0x1C), E.u32(text_item + 0x1C)
    check('text line wrapped', text != orig_text, True)
    hover = E.find('55 56 57 8B F1 FF 15 ? ? ? ? 8B 7E 38 33 ED 3B FD 0F 84 ? ? ? ? 8B 4F 2C 81 E1 FF FF 00 00')[0]
    bubble = E.u32(hover + 0x238)
    settext = hover + 0x262 + 5 + E.i32(hover + 0x263)
    ct = E.find('8B 15 ? ? ? ? 83 EC 0C 83 7C 24 10 00 53 8B 1D ? ? ? ? 56 8B F1 75 17 83 FB 10 75 12 83 FA 01 0F 84 ? ? ? ?')[0]
    rnum = ct + 0x1083 + 5 + E.i32(ct + 0x1084)
    rgm = ct + 0x10AB + 5 + E.i32(ct + 0x10AC)
    rtxt = ct + 0x10D9 + 5 + E.i32(ct + 0x10DA)
    drawbuf = E.u32(ct + 0x124F)
    surface = E.u32(ct + 0x1245)
    bottom = E.u32(orig_text + 6)
    calls = []

    def stub(name, ret_bytes, args):
        def hook(cpu):
            calls.append((name, [cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(args)],
                          H.u32(drawbuf), H.u32(surface)))
            cpu.eip = cpu.pop(); cpu.r['esp'] = (cpu.r['esp'] + ret_bytes) & MASK
        return hook
    H.cpu.hooks[orig_render] = stub('status', 0, 1)
    H.cpu.hooks[w.rren] = stub('button', 0, 1)

    def orig_text_hook(cpu):
        calls.append(('text', [cpu.m.u32(cpu.r['esp'] + 4)], 0, 0))
        if cpu.m.u32(cpu.r['esp'] + 4) == 0:   # the game moves a map layer line by the camera
            H.put32(w.BX, H.u32(w.BX) + 1000); H.put32(w.BX + 4, H.u32(w.BX + 4) + 2000)
            H.put32(surface, 1)
        H.put32(drawbuf, 1)
        cpu.eip = cpu.pop()
    H.cpu.hooks[orig_text] = orig_text_hook

    def set_text(cpu):
        a = [cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(6)]
        calls.append(('set', a, 0, 0))
        H.put32(bottom, a[0])
        cpu.eip = cpu.pop(); cpu.r['esp'] = (cpu.r['esp'] + 0x18) & MASK
    H.cpu.hooks[settext] = set_text
    H.cpu.hooks[rnum] = stub('number', 0x24, 9)
    H.cpu.hooks[rgm] = stub('picture', 0x10, 4)
    H.cpu.hooks[rtxt] = stub('shadow', 0x24, 9)

    bid = 14
    w.building(bid, 37, 1, 90, 90, 1400, cur=40, mx=100)
    H.put32(w.COSTS + 37 * 20 + 16, 300)
    H.put32(w.SELECTED, bid); H.put32(w.LOCAL, 1)
    H.put32(w.GOLD_RES + 0x39F4, 777)
    wood = E.u32(w.ract + 0x81); stone = E.u32(w.ract + 0xA6)
    H.put32(wood, 0); H.put32(stone, 12)
    H.put32(bubble, 1)
    ox, oy = 100, 50

    def at(item_x, item_y):
        for k, val in enumerate((item_x + ox, item_y + oy, 0, 0, 0)):
            H.put32(w.BX + 4 * k, val)

    seen = {}

    def rec(cpu):
        seen['xy'] = (H.u32(w.BX) - ox, H.u32(w.BX + 4) - oy)
        cpu.eip = cpu.pop()
    H.cpu.hooks[w.rren] = rec
    H.put32(w.MOUSE + 0x10, 0); H.put32(w.MOUSE + 0x14, 0)
    for tab, want in ((14, (340, 466)), (4, (210, 466)), (3, (390, 466)), (23, (420, 466)),
                      (24, (420, 466)), (44, None), (1, None), (200, (340, 466))):
        H.put32(w.TAB, tab)
        at(25, 570)
        seen.clear()
        H.run(render, stack=[0])
        check('tab %d button place' % tab, seen.get('xy'), want)
    # barracks and mercenary post: drawn from their own text line (20,424), after the portraits
    for tab, want in ((1, (230, 422)), (44, (230, 562))):
        H.put32(w.TAB, tab)
        at(20, 424)
        seen.clear()
        H.run(text, stack=[1])
        check('tab %d button place (late)' % tab, seen.get('xy'), want)
        at(20, 415)
        seen.clear()
        H.run(text, stack=[0])
        check('tab %d: not from the shared line' % tab, seen.get('xy'), None)
    H.cpu.hooks[w.rren] = stub('button', 0, 1)

    def draw(tab):
        H.put32(w.TAB, tab)
        at(25, 570)
        calls.clear()
        H.run(render, stack=[0])

    # hover on the granary's button, then the shared text line (map layer)
    H.put32(w.MOUSE + 0x10, 210 + ox + 3); H.put32(w.MOUSE + 0x14, 466 + oy + 3)
    draw(4)
    H.put32(bottom, 0); H.put32(surface, 0); H.put32(drawbuf, 1)
    at(20, 415)
    calls.clear()
    cpu = H.run(text, stack=[0])
    check('stack balanced', cpu.r['esp'], 0x70100000 - 4)
    names = [c[0] for c in calls]
    check('cost text set, then drawn', names[:2], ['set', 'text'])
    check('the tower repair text', calls[0][1], [8, 8, 257, 0, 0x32, 0xFFFFFFFF])
    check('gold part drawn', names[2:], ['number', 'picture', 'shadow', 'number', 'shadow'])
    num = calls[2]
    check('gold cost 60% of 300 = 180', num[1][0], 180)
    check('after the stone part', num[1][1], 20 + ox + 1000 + 0x1E + 0x40)
    check('map layer text', num[3], 1)
    check('gold coin picture', calls[3][1][:2], [0x2E, 0x7C])
    check('coin on the same picture layer as the game left it', calls[3][2], 1)
    check('gold the player has', calls[5][1][0], 777)

    # not hovered: the game's own text alone
    H.put32(w.MOUSE + 0x10, 0)
    draw(4)
    H.put32(bottom, 0)
    at(20, 415)
    calls.clear()
    H.run(text, stack=[0])
    check('not hovered: nothing set', [c[0] for c in calls], ['text'])
    # help texts off: nothing set
    H.put32(w.MOUSE + 0x10, 210 + ox + 3)
    draw(4)
    H.put32(bubble, 0)
    at(20, 415)
    calls.clear()
    H.run(text, stack=[0])
    check('help texts off: nothing set', [c[0] for c in calls], ['text'])
    H.put32(bubble, 1)

    # barracks: button and text come from its own line (param 1), on the screen layer
    H.put32(w.MOUSE + 0x10, 230 + ox + 3); H.put32(w.MOUSE + 0x14, 422 + oy + 3)
    H.put32(w.TAB, 1)
    H.put32(w.TAB - 4, 0x10)
    H.put32(surface, 0); H.put32(drawbuf, 1)
    at(20, 424)
    calls.clear()
    H.run(text, stack=[1])
    names = [c[0] for c in calls]
    check('barracks own line: button, text set, drawn', names[:3], ['button', 'set', 'text'])
    gold = [c for c in calls if c[0] == 'number']
    check('barracks gold part on the screen layer', gold and gold[0][3], 0)
    check('barracks gold part at the line, no camera', gold and gold[0][1][1], 20 + ox + 0x1E + 0x40)
    coin = [c for c in calls if c[0] == 'picture']
    check('barracks coin on the screen picture layer', coin and coin[0][2], 0)
    check('picture layer put back', H.u32(drawbuf), 1)
    # the shared line in the barracks draws nothing of ours and no gold part
    H.put32(bottom, 8)
    at(20, 415)
    calls.clear()
    H.run(text, stack=[0])
    check('barracks shared line: no gold part', 'picture' in [c[0] for c in calls], False)
    # a building without a gold price: no gold part
    H.put32(w.COSTS + 37 * 20 + 16, 0)
    H.put32(w.TAB, 4)
    H.put32(bottom, 8)
    calls.clear()
    H.run(text, stack=[0])
    check('no gold price: no gold part', 'picture' in [c[0] for c in calls], False)

    # the game's own cost text: which layer a repair cost line goes on
    stubsite = ct + 0x3B
    check('layer test hooked', H.m.read(stubsite, 1), b'\xE9')
    stub_at = stubsite + 5 + struct.unpack('<i', H.m.read(stubsite + 1, 4))[0]
    code = H.m.read(stub_at, 40)
    i = code.find(b'\x80\x3D')
    flag = struct.unpack('<I', code[i + 2:i + 6])[0]
    screen_path, map_path = ct + 0x80, ct + 0x41
    where = []
    for addr, name in ((screen_path, 'screen'), (map_path, 'map')):
        def hk(cpu, name=name):
            where.append(name)
            cpu.eip = SENTINEL
        H.cpu.hooks[addr] = hk
    H.put32(bottom, 8); H.put32(bottom + 4, 8); H.put32(bottom + 8, 257)
    H.put32(w.TAB - 4, 0x10); H.put32(w.TAB, 14)
    for flagv, want in ((1, 'screen'), (0, 'map')):
        H.put8(flag, flagv); where.clear()
        H.run(ct, regs={'ecx': bottom}, stack=[1])
        check('cost line layer with flag %d' % flagv, where, [want])
    H.put32(bottom, 6); H.put8(flag, 0); where.clear()
    H.run(ct, regs={'ecx': bottom}, stack=[1])
    check('other screen kinds unchanged', where, ['screen'])
    H.put32(bottom, 9); where.clear()
    H.run(ct, regs={'ecx': bottom}, stack=[1])
    check('other map kinds unchanged', where, ['map'])


for ext in (False, True):
    run(ext)
print('%d checks, %d failed' % (COUNT[0], len(FAILS)))
