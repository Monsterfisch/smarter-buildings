"""The stable panel: "in use" counts the stable's knights alive, and the next-horse bar with the
time left - running the game's own panel function, its drawing calls recorded."""
import struct
from test_behaviour import W, check, FAILS, COUNT
from harness import MASK


def run(ext):
    print('== ' + ('Extreme' if ext else 'Crusader'))
    w = W(ext); H = w.H; E = w.E
    stable = E.find('A1 ? ? ? ? 8B 0D ? ? ? ? 56 8B 35 ? ? ? ? 6A 00 6A 00 6A 10 6A 00 6A 00 05 D3 01 00 00 50 83 C1 19 51 6A 00 6A 35')[0]
    bar = E.find('83 EC 20 A1 ? ? ? ? 33 C4 89 44 24 1C 8B 0D ? ? ? ? 66 8B 15 ? ? ? ? 69 C9 2C 03 00 00')[0]
    tgt = lambda site: site + 5 + E.i32(site + 1)
    gettext = tgt(stable + 0x2F)
    rtext = tgt(stable + 0x3A)
    rnum = tgt(stable + 0x7D)
    border, box, sprintf = tgt(bar + 0x83), tgt(bar + 0xA9), tgt(bar + 0xEC)
    menu_y, menu_x = E.u32(stable + 1), E.u32(stable + 7)
    H.put32(menu_x, 100); H.put32(menu_y, 50)
    calls = []

    def stub(name, ret_bytes, args):
        def hook(cpu):
            calls.append((name, [cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(args)]))
            cpu.r['eax'] = 0x1234
            cpu.eip = cpu.pop(); cpu.r['esp'] = (cpu.r['esp'] + ret_bytes) & MASK
        return hook
    H.cpu.hooks[gettext] = stub('gettext', 8, 2)
    H.cpu.hooks[rtext] = stub('text', 0x20, 8)
    H.cpu.hooks[rnum] = stub('number', 0x20, 8)
    H.cpu.hooks[border] = stub('border', 0x14, 5)
    H.cpu.hooks[box] = stub('box', 0x14, 5)
    H.cpu.hooks[sprintf] = stub('sprintf', 0, 4)

    bid = 5
    b = w.building(bid, 35, 1, 60, 60, 1234)
    H.put8(b + 0x297, 4)
    knight_horse = w.call_target(w.recruit + 0xE)
    for k, unit in enumerate((20, 21, 22)):
        w.make_unit(unit, 1, 1, 61, 61, 5000 + k)
        H.put8(b + 0x297, 4)
        H.run(knight_horse, regs={'ecx': w.GAMESTATE}, stack=[1, unit])
    H.put32(w.SELECTED, bid)
    H.put16(w.unit(22) + 0x8C, 0)            # one of the three knights died

    def draw():
        calls.clear()
        cpu = H.run(stable, regs={'ebx': 0x11, 'esi': 0x22, 'edi': 0x33, 'ebp': 0x44})
        check('registers kept', (cpu.r['ebx'], cpu.r['esi'], cpu.r['edi'], cpu.r['ebp']), (0x11, 0x22, 0x33, 0x44))
        check('stack balanced', cpu.r['esp'], 0x70100000)
        return calls

    c = draw()
    nums = [x[1][0] for x in c if x[0] == 'number']
    check('available and in use', nums, [3, 2])
    texts = [x[1] for x in c if x[0] == 'gettext']
    check('"in use" plural (2)', texts[-1], [0x35, 2])
    # breeding: stalls 3 + 2 knights = 5 alive -> 9 x 60 s; a third of it done
    site = E.find('66 01 9E ? ? ? ? 0F B7 86 ? ? ? ? 66 3D 26 02 7E ?')[0]
    code = w.jump_target(site)
    H.cpu.hooks[site + 20] = lambda cpu: setattr(cpu, 'eip', 0x7FFFFFF0)
    wait = site + 20 + E.data[E.va2off(site + 19)]
    H.cpu.hooks[wait] = lambda cpu: setattr(cpu, 'eip', 0x7FFFFFF0)
    H.put32(w.TICKS, 64 - bid)                # a recount tick: the stable's knights are counted
    H.run(code, regs={'esi': bid * 0x32C, 'edi': bid, 'ebx': 1, 'ebp': 0})
    body = H.m.read(code, 200)
    i = body.find(bytes([0xFF, 0x04, 0xBD]))   # inc dword [COUNTERS + edi*4]
    counters = struct.unpack('<I', body[i + 3:i + 7])[0] if i >= 0 else None
    check('found the counter', counters is not None, True)
    H.put32(counters + 4 * bid, 1650)
    c = draw()
    boxes = [x[1] for x in c if x[0] in ('border', 'box')]
    x0, y0 = 100 + 0xAF, 50 + 0x231
    check('bar frame', boxes[0], [x0, y0, x0 + 51, y0 + 11, H.u16(E.u32(bar + 0x5D))])
    check('bar background', boxes[1][:4], [x0 + 1, y0 + 1, x0 + 50, y0 + 10])
    check('bar filled a third', boxes[2][:4], [x0 + 1, y0 + 1, x0 + 16, y0 + 10])
    check('no time text', [x for x in c if x[0] in ('sprintf',)], [])
    # full stalls: full bar, no time
    H.put8(b + 0x297, 4)
    c = draw()
    boxes = [x[1] for x in c if x[0] in ('border', 'box')]
    check('full stalls: full bar', boxes[2][:4], [x0 + 1, y0 + 1, x0 + 50, y0 + 10])


for ext in (False, True):
    run(ext)
print('%d checks, %d failed' % (COUNT[0], len(FAILS)))
