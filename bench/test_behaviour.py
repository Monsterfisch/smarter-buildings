"""Runs smarter-buildings' injected code (and the game's own functions where practical) in the
emulator, on both exes. Addresses are worked out here independently of the module."""
import sys, struct
from harness import Host, SENTINEL, MASK

FAILS = []
COUNT = [0]


def check(label, got, want):
    COUNT[0] += 1
    if got != want:
        FAILS.append(label)
        print('  FAIL %s: got %r want %r' % (label, got, want))


def s16(v):
    return struct.unpack('<h', struct.pack('<H', v & 0xFFFF))[0]


class W:
    def __init__(self, ext, config=None, aic=True):
        H = self.H = Host(extreme=ext, config=config, aic=aic)
        E = self.E = H.E
        f = lambda p: E.find(p)[0]
        self.acc = f('83 EC 0C 8B 44 24 10 85 C0 57 8B F9 89 7C 24 04 7F 09')
        self.ract = f('A1 ? ? ? ? 56 57 50 B9 ? ? ? ? 33 FF E8 ? ? ? ? 85 C0 75 03 8D 78 01')
        self.rren = f('A1 ? ? ? ? 56 8B F0 69 F6 2C 03 00 00 0F BF 8E ? ? ? ? 57 33 FF 3B 0D')
        self.rexec = f('8B 44 24 08 57 8B F8 69 FF 2C 03 00 00 8B 8F ? ? ? ? 3B 4C 24 18')
        self.rcost = f('51 8B 44 24 08 69 C0 2C 03 00 00 55 8B E9 0F B7 94 28')
        self.fire = f('83 EC 08 53 55 57 8B 7C 24 18 69 FF 90 04 00 00 8B 87 ? ? ? ? 8B E9')
        self.dest = f('83 EC 08 8B 44 24 0C 8B D0 69 D2 90 04 00 00')
        self.det = f('83 EC 2C 53 55 8B 6C 24 38 69 ED 2C 03 00 00 56 8B F1')
        self.setpos = f('53 8B 5C 24 0C 81 FB 8F 01 00 00 55 8B E9 0F 87')
        self.recruit = f('83 7C 24 18 FF 75 25 55 57 B9 ? ? ? ? E8 ? ? ? ? 66 89 86')
        self.bupd = f('0F BF 80 E6 00 00 00 8B 0C 85 ? ? ? ? FF D1 8B 0D ? ? ? ?')
        bs = E.find('83 3D ? ? ? ? 00 8D 84 37 ? ? ? ? 8D 8C 37 ? ? ? ? 74 0C 66 C7 00 16 00 66 C7 01 16 00')[0]
        self.blacksmith = (H.m.read(bs + 0x1A, 1)[0], H.m.read(bs + 0x1F, 1)[0])
        u = E.u32
        self.BS = u(self.ract + 9)
        self.B = self.BS + 0x14
        self.UNITS = u(self.fire + 0x12) - 0xD4
        self.US = self.UNITS - 0x614
        self.SELECTED = u(self.ract + 1)
        self.LOCAL = u(self.ract + 0x7B)
        self.WOOD_RES = u(self.rexec + 0x3B)
        self.GOLD_RES = self.WOOD_RES + 13 * 4
        self.COSTS = u(self.rcost + 0x49)
        self.AREAS = u(self.acc + 0x41)
        self.ROWS = u(self.acc + 0x5D)
        self.HEIGHTS = u(self.acc + 0x65)
        self.TICKS = u(E.find('8B 87 50 0A 00 00 8B 8F 98 09 00 00 8B 15 ? ? ? ?')[0] + 14)
        self.CURRENT = u(self.bupd + 0x12)
        self.AI_TYPES = u(E.find('69 C0 F4 39 00 00 8B 88 ? ? ? ? 69 C9 A4 02 00 00')[0] + 8)
        self.GAMESTATE = u(self.recruit + 10)
        self.ENEMY = self.ract + 0x54 + 5 + E.i32(self.ract + 0x55)
        screen = u(E.find('F7 C1 00 00 00 40 0F 85 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 85 C0 0F 84 ? ? ? ? 83 3D ? ? ? ? FF')[0] + 13)
        self.TAB = screen + 0x10
        mi = E.find('8B 56 10 8B 46 4C 8B 4E 0C 52 8B 50 08 03 56 08 8B 40 04 03 46 04 51 52 50 B9 ? ? ? ? E8')[0]
        self.MOUSE = u(mi + 0x1A)
        self.BX = u(self.rren + 0xE1)
        # a small map: rows of 400 tiles
        for y in range(400):
            H.put32(self.ROWS + y * 12, y * 400)
        H.put32(self.BS + 8, 40)          # building slots in use
        H.put32(self.US, 60)              # unit slots in use
        H.put32(self.TICKS, 1000)

    def bld(self, i):
        return self.B + i * 0x32C

    def unit(self, i):
        return self.UNITS + i * 0x490

    def building(self, i, btype, owner, x, y, uid, cur=100, mx=100, fire=0):
        H = self.H; b = self.bld(i)
        H.put16(b + 0xD0, 2); H.put16(b + 0xD2, btype); H.put16(b + 0xD6, owner)
        H.put32(b + 0xD8, uid); H.put16(b + 0xEE, x); H.put16(b + 0xF0, y)
        H.put16(b + 0x10C, cur); H.put16(b + 0x10E, mx); H.put16(b + 0x2BE, fire)
        H.put16(b + 0xFE, x); H.put16(b + 0x100, y)
        return b

    def make_unit(self, i, utype, owner, x, y, uid, state=0):
        H = self.H; u = self.unit(i)
        H.put16(u + 0x8C, 2); H.put16(u + 0x8E, utype); H.put16(u + 0x96, owner)
        H.put32(u + 0x98, uid); H.put16(u + 0xC4, x); H.put16(u + 0xC6, y)
        H.put32(u + 0xD4, y * 400 + x); H.put16(u + 0x2C0, state)
        return u

    def call_target(self, site):
        return site + 5 + struct.unpack('<i', self.H.m.read(site + 1, 4))[0]

    def jump_target(self, site):
        assert self.H.m.read(site, 1) == b'\xE9', hex(site)
        return self.call_target(site)


def test_blacksmith(w):
    print(' blacksmith')
    check('new blacksmith makes maces', w.blacksmith, (0x15, 0x15))


def test_stables(w):
    print(' stables')
    H = w.H
    b = w.building(5, 35, 1, 60, 60, 1234)
    H.put8(b + 0x297, 4); H.put8(b + 0x2A7, 0)
    w.make_unit(7, 28, 1, 61, 61, 999)
    link = w.E.find('53 8B 1D ? ? ? ? 55 56 BE 01 00 00 00 3B DE 57 8B E9')[0]
    assert w.E.bytes_(link + 0x66, 3) == bytes([0x66, 0x83, 0x84]), w.E.bytes_(link + 0x66, 4).hex()
    horses = w.GAMESTATE + w.E.u32(link + 0x6A) + 1 * 0x39F4
    H.put16(horses, 4)
    wrapper = w.call_target(w.recruit + 0xE)
    cpu = H.run(wrapper, regs={'ecx': w.GAMESTATE}, stack=[1, 7])
    check('the knight is not tied to the stable', cpu.r['eax'], 0)
    check('the stall is free (horses in the stable)', H.m.read(b + 0x297, 1)[0], 3)
    check('no stall kept for the knight', H.m.read(b + 0x2A7, 1)[0], 0)
    check('the knight is not listed in the stable', [H.u16(b + 0x2E0 + 2 * k) for k in range(4)], [0, 0, 0, 0])
    check('one horse fewer to recruit with', H.u16(horses), 3)
    check('stack balanced', cpu.r['esp'], 0x70100000)
    # a stable without free horses: nothing to take
    H.put8(b + 0x297, 0)
    cpu = H.run(wrapper, regs={'ecx': w.GAMESTATE}, stack=[1, 8])
    check('no horse, no stable', cpu.r['eax'], 0)
    check('stack balanced (none)', cpu.r['esp'], 0x70100000)


def test_firemen(w):
    print(' firemen')
    H = w.H
    A = w.building(3, 2, 1, 100, 100, 301, fire=50)
    Bb = w.building(4, 2, 1, 110, 100, 401, fire=50)
    for (x, y) in ((100, 100), (110, 100), (101, 100), (102, 100)):
        H.put16(w.AREAS + (y * 400 + x) * 2, 5)
    w.make_unit(10, 53, 1, 101, 100, 1010, state=1)
    other = w.make_unit(11, 53, 1, 102, 100, 1011, state=3)
    H.put16(other + 0x39E, 0); H.put32(other + 0x3A0, 0)
    cpu = H.run(w.fire, regs={'ecx': w.BS}, stack=[10])
    check('alone: nearest fire', cpu.r['eax'], 3)
    H.put16(other + 0x39E, 3); H.put32(other + 0x3A0, 301)
    cpu = H.run(w.fire, regs={'ecx': w.BS}, stack=[10])
    check('another fireman on the nearest: the next fire', cpu.r['eax'], 4)
    check('stack balanced', cpu.r['esp'], 0x70100000)
    H.put16(other + 0x2C0, 7)
    cpu = H.run(w.fire, regs={'ecx': w.BS}, stack=[10])
    check('other fireman doing something else: nearest again', cpu.r['eax'], 3)
    H.put16(A + 0x2BE, 0); H.put16(Bb + 0x2BE, 0)


def test_unstuck(w):
    print(' stuck workers')
    H = w.H; E = w.E
    bid = 7
    b = w.building(bid, 13, 1, 50, 50, 707)
    doors = [(49, 51), (50, 49), (51, 49), (53, 50), (53, 52)]
    good = {(53, 52)}
    areas = {(49, 51): 1, (50, 49): 1, (51, 49): 2, (53, 50): 2, (53, 52): 3}
    for (x, y), a in areas.items():
        H.put16(w.AREAS + (y * 400 + x) * 2, a)
    calls = {'det': 0, 'pos': [], 'search': []}

    def determine(cpu):
        i = cpu.m.u32(cpu.r['esp'] + 4)
        bb = w.bld(i)
        idx = H.u16(bb + 0xFC) % len(doors)
        H.put16(bb + 0xFC, idx)
        x, y = doors[idx]
        H.put16(bb + 0xFE, x); H.put16(bb + 0x100, y)
        calls['det'] += 1
        cpu.r['eax'] = 1
        cpu.eip = cpu.pop(); cpu.r['esp'] += 0xC
    H.cpu.hooks[w.det] = determine

    def setpos(cpu):
        a = [cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(4)]
        calls['pos'].append(tuple(a[:3]))
        u = w.unit(a[0]); H.put16(u + 0xC4, a[1]); H.put16(u + 0xC6, a[2])
        cpu.eip = cpu.pop(); cpu.r['esp'] += 0x10
    H.cpu.hooks[w.setpos] = setpos

    def search(cpu):   # the function body after its first 7 bytes: esp points at its 8 bytes of locals
        esp = cpu.r['esp']
        unit = cpu.m.u32(esp + 0xC)
        u = w.unit(unit)
        here = (H.u16(u + 0xC4), H.u16(u + 0xC6))
        calls['search'].append(here)
        cpu.r['eax'] = 1 if here in good else 0
        cpu.eip = cpu.m.u32(esp + 8)
        cpu.r['esp'] = (esp + 8 + 4 + 0x10) & MASK
    H.cpu.hooks[w.dest + 7] = search

    def go(unit, mode=0):
        calls['det'] = 0; calls['pos'] = []; calls['search'] = []
        return H.run(w.dest, regs={'ecx': w.US, 'ebx': 0x1111, 'esi': 0x2222, 'edi': 0x3333, 'ebp': 0x4444},
                     stack=[unit, 90, 90, mode])

    def reset_door():
        H.put16(b + 0xFE, 49); H.put16(b + 0x100, 51); H.put16(b + 0xFC, 0)

    reset_door()
    u = w.make_unit(30, 19, 1, 49, 51, 3030)
    H.put16(u + 0x338, bid); H.put32(u + 0x368, 707)
    H.put32(w.TICKS, 1000)
    cpu = go(30)
    check('a door that works is found', cpu.r['eax'], 1)
    check('the door moved there', (H.u16(b + 0xFE), H.u16(b + 0x100)), (53, 52))
    check('the worker came out of it', (H.u16(u + 0xC4), H.u16(u + 0xC6)), (53, 52))
    check('doors in the failing area were not tried', calls['search'], [(49, 51), (51, 49), (53, 52)])
    check('registers kept', (cpu.r['ebx'], cpu.r['esi'], cpu.r['edi'], cpu.r['ebp']), (0x1111, 0x2222, 0x3333, 0x4444))
    check('stack balanced', cpu.r['esp'], 0x70100000)

    # now the new door works: no more door walking
    cpu = go(30)
    check('a working door: one search', (cpu.r['eax'], calls['det']), (1, 0))

    # no door works: everything goes back
    good.clear()
    reset_door(); H.put16(u + 0xC4, 49); H.put16(u + 0xC6, 51)
    H.put32(w.TICKS, 1300)
    cpu = go(30)
    check('no door works: the search fails', cpu.r['eax'], 0)
    check('the door is back', (H.u16(b + 0xFE), H.u16(b + 0x100), H.u16(b + 0xFC)), (49, 51, 0))
    check('the worker is back on it', (H.u16(u + 0xC4), H.u16(u + 0xC6)), (49, 51))
    check('stack balanced (fail)', cpu.r['esp'], 0x70100000)

    # not again within 5 s
    H.put32(w.TICKS, 1350)
    cpu = go(30)
    check('rate limited', (cpu.r['eax'], calls['det']), (0, 0))
    # a new game (ticks restart) is not held up
    H.put32(w.TICKS, 500)
    cpu = go(30)
    check('a new game is not held up', calls['det'] > 0, True)
    # not standing on the door
    H.put32(w.TICKS, 5000)
    H.put16(u + 0xC4, 60)
    cpu = go(30)
    check('away from the door: left alone', calls['det'], 0)
    H.put16(u + 0xC4, 49)
    # other modes are left alone
    H.put32(w.TICKS, 9000)
    cpu = go(30, mode=2)
    check('mode 2 left alone', calls['det'], 0)
    # soldiers are left alone
    H.put16(u + 0x8E, 24)
    H.put32(w.TICKS, 12000)
    cpu = go(30)
    check('not a worker: left alone', calls['det'], 0)
    H.put16(u + 0x8E, 19)
    del H.cpu.hooks[w.det]; del H.cpu.hooks[w.setpos]; del H.cpu.hooks[w.dest + 7]


def test_repair_exec(w):
    print(' repair command')
    H = w.H
    bid = 9
    b = w.building(bid, 37, 1, 70, 70, 555, cur=500, mx=1000)
    H.put32(w.COSTS + 37 * 20 + 16, 400)     # a church costs 400 gold here
    p = 1 * 0x39F4
    H.put32(w.GOLD_RES + p, 1000)
    cpu = H.run(w.rexec, stack=[1, bid, 0, 0, 555])
    check('repaired', H.u16(b + 0x10C), 1000)
    check('half the gold price paid', H.u32(w.GOLD_RES + p), 800)
    check('stack balanced', cpu.r['esp'], 0x70100000 - 0x14)
    H.put16(b + 0x10C, 500)
    H.put32(w.GOLD_RES + p, 100)
    H.run(w.rexec, stack=[1, bid, 0, 0, 555])
    check('not enough gold: not repaired', H.u16(b + 0x10C), 500)
    check('not enough gold: nothing paid', H.u32(w.GOLD_RES + p), 100)
    H.put32(w.GOLD_RES + p, 1000)
    H.run(w.rexec, stack=[1, bid, 0, 0, 556])
    check('wrong uid: nothing', (H.u16(b + 0x10C), H.u32(w.GOLD_RES + p)), (500, 1000))


def test_fire_blocks(w):
    print(' burning buildings')
    H = w.H
    b = w.building(12, 2, 1, 80, 80, 1200, cur=50, mx=100, fire=0)
    H.put32(w.SELECTED, 12)
    wrapper = w.call_target(w.ract + 0x54)
    check('the action asks the fire test', wrapper != w.ENEMY, True)
    check('the drawing asks the fire test', w.call_target(w.rren + 0x6F), wrapper)
    H.stub(w.ENEMY, 0, 0x10)
    cpu = H.run(wrapper, regs={'ecx': 0}, stack=[1, 80, 80, 15])
    check('not burning: the game decides', cpu.r['eax'], 0)
    H.put16(b + 0x2BE, 30)
    cpu = H.run(wrapper, regs={'ecx': 0}, stack=[1, 80, 80, 15])
    check('burning: counts as enemy near', cpu.r['eax'], 1)
    check('stack balanced', cpu.r['esp'], 0x70100000)
    H.put16(b + 0x2BE, 0)
    del H.cpu.hooks[w.ENEMY]


def find_menu(w):
    E = w.E
    pat = ' '.join('%02X' % c for c in struct.pack('<6I', 3, 340, 466, 100, 28, w.ract))
    it = E.find(pat)[0]
    while E.u32(it - 0x50) != 0x66:
        it -= 0x50
    start = it
    while not (E.u32(it) == 3 and E.i32(it + 4) == 25 and E.i32(it + 8) == 570):
        it += 0x50
    return start, it


def test_button(w):
    print(' repair button')
    H = w.H
    start, status = find_menu(w)
    render = H.u32(status + 0x1C)
    frame = H.u32(start + 0x14)
    check('status line wrapped', render != w.E.u32(status + 0x1C), True)
    check('frame item wrapped', frame != w.E.u32(start + 0x14), True)
    orig_render, orig_frame = w.E.u32(status + 0x1C), w.E.u32(start + 0x14)
    seen = {}

    def rec(name, ret=0):
        def hook(cpu):
            seen[name] = [H.u32(w.BX + 4 * k) for k in range(5)]
            cpu.r['eax'] = ret
            cpu.eip = cpu.pop()
        return hook
    H.cpu.hooks[orig_render] = rec('status')
    H.cpu.hooks[w.rren] = rec('button')
    H.cpu.hooks[w.ract] = rec('action')
    H.cpu.hooks[orig_frame] = rec('frame')
    bid = 14
    b = w.building(bid, 13, 1, 90, 90, 1400, cur=40, mx=100)
    H.put32(w.SELECTED, bid); H.put32(w.LOCAL, 1); H.put32(w.TAB, 13)
    ox, oy = 100, 50
    for k, val in enumerate((25 + ox, 570 + oy, 0, 0, 0)):
        H.put32(w.BX + 4 * k, val)
    H.put32(w.MOUSE + 0x10, 340 + ox + 5); H.put32(w.MOUSE + 0x14, 466 + oy + 5)

    def draw():
        seen.clear()
        cpu = H.run(render, stack=[0])
        check('stack balanced (draw)', cpu.r['esp'], 0x70100000 - 4)

    draw()
    check('status line still drawn', 'status' in seen, True)
    check('button drawn at its place, hovered', seen.get('button'), [340 + ox, 466 + oy, 100, 28, 1])
    check('globals put back', [H.u32(w.BX + 4 * k) for k in range(5)], [25 + ox, 570 + oy, 0, 0, 0])
    H.put32(w.MOUSE + 0x34, 1)
    seen.clear()
    H.run(frame, stack=[0])
    check('a click on it repairs', 'action' in seen, True)
    check('the click is used up', H.u32(w.MOUSE + 0x34), 0)
    check('the frame item still runs', 'frame' in seen, True)
    # no button drawn in the last frame: clicks pass
    H.put32(w.MOUSE + 0x34, 1)
    seen.clear()
    H.run(frame, stack=[0])
    check('no button last frame: no repair', 'action' in seen, False)
    check('no button last frame: click kept', H.u32(w.MOUSE + 0x34), 1)
    # a click beside it
    draw()
    H.put32(w.MOUSE + 0x10, 340 + ox + 150)
    seen.clear()
    H.run(frame, stack=[0])
    check('click beside: no repair', 'action' in seen, False)
    H.put32(w.MOUSE + 0x10, 340 + ox + 5)
    # cases with no button
    for label, setup, undo in (
            ('undamaged', lambda: H.put16(b + 0x10C, 100), lambda: H.put16(b + 0x10C, 40)),
            ("someone else's", lambda: H.put32(w.LOCAL, 2), lambda: H.put32(w.LOCAL, 1)),
            ('towers have their own', lambda: H.put32(w.TAB, 36), lambda: H.put32(w.TAB, 13)),
            ('nothing selected', lambda: H.put32(w.SELECTED, 0), lambda: H.put32(w.SELECTED, bid))):
        setup(); draw(); undo()
        check(label + ': no button', 'button' in seen, False)
    for a in (orig_render, w.rren, w.ract, orig_frame):
        del H.cpu.hooks[a]


def test_buildings(w):
    print(' building update: doors and AI repairs')
    H = w.H
    hook = w.bupd + 0x10
    code = w.jump_target(hook)
    resume = hook + 6
    acc = []

    def accessible(cpu):
        acc.append(cpu.m.u32(cpu.r['esp'] + 4))
        cpu.r['eax'] = 1
        cpu.eip = cpu.pop(); cpu.r['esp'] += 8
    H.cpu.hooks[w.acc] = accessible
    execs = []

    def exe(cpu):
        execs.append([cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(5)])
        cpu.eip = cpu.pop()
    H.cpu.hooks[w.rexec] = exe
    enemy = [0]
    H.cpu.hooks[w.ENEMY] = lambda cpu: (cpu.r.__setitem__('eax', enemy[0]), setattr(cpu, 'eip', cpu.pop()),
                                        cpu.r.__setitem__('esp', (cpu.r['esp'] + 0x10) & MASK))

    def tick(bid, t):
        acc.clear(); execs.clear()
        H.put32(w.CURRENT, bid)
        H.put32(w.TICKS, t)
        cpu = H.run(code, until=resume, regs={'esi': w.BS, 'edi': 1, 'ebx': 0, 'ebp': 5})
        check('registers kept', (cpu.r['esi'], cpu.r['edi'], cpu.r['ebx'], cpu.r['ebp'], cpu.r['ecx']),
              (w.BS, 1, 0, 5, bid))
        return cpu

    house = 20
    w.building(house, 1, 1, 30, 30, 2000)
    tick(house, 64 * 100 - house)
    check('a house door is checked', acc, [house])
    tick(house, 64 * 100 - house + 1)
    check('...every 64 ticks', acc, [])
    w.building(21, 13, 1, 30, 40, 2100)
    tick(21, 64 * 100 - 21)
    check('a workshop is left to its workers', acc, [])
    w.building(22, 19, 1, 30, 50, 2200)
    tick(22, 64 * 100 - 22)
    check('a granary door is checked', acc, [22])

    # AI repairs: player 2 is AI character 3
    E = w.E
    buy = E.find('53 8B 5C 24 10 55 8B 6C 24 10 56 8B 74 24 10 57 53 55 56 B9 ? ? ? ? E8 ? ? ? ? 53 55 56 B9')[0]
    price_fn = buy + 0x18 + 5 + E.i32(buy + 0x19)
    prices = {2: 4, 4: 12}
    bought, priced = [], []
    buy_ok = [1]

    def price(cpu):
        a = [cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(3)]
        priced.append(a)
        cpu.r['eax'] = prices[a[1]] * a[2]
        cpu.eip = cpu.pop(); cpu.r['esp'] = (cpu.r['esp'] + 0xC) & MASK
    H.cpu.hooks[price_fn] = price

    def buy_goods(cpu):
        a = [cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(3)]
        bought.append(a)
        cpu.r['eax'] = buy_ok[0]
        cpu.eip = cpu.pop(); cpu.r['esp'] = (cpu.r['esp'] + 0xC) & MASK
    H.cpu.hooks[buy] = buy_goods

    def ai_tick(t):
        bought.clear(); priced.clear()
        tick(21, t)

    p2 = 2 * 0x39F4
    H.put32(w.AI_TYPES + p2, 3)
    H.put32(w.GOLD_RES + p2, 6000)
    H.put32(w.WOOD_RES + p2, 0); H.put32(w.WOOD_RES + 8 + p2, 0)
    H.put32(w.COSTS + 61 * 20 + 4, 100)    # a tower costs 100 stone here
    H.put32(w.COSTS + 2 * 20, 20)          # a house 20 wood
    bid = 23
    tb = w.building(bid, 61, 2, 40, 40, 2300, cur=30, mx=100)       # 70% damaged
    w.building(24, 13, 2, 50, 40, 2400, cur=90, mx=100)             # 10%: below the threshold
    hb = w.building(25, 2, 2, 60, 40, 2500, cur=60, mx=100)         # 40%
    t = 64 * 200
    ai_tick(t)
    check('the AI repairs its most damaged building', [e[:5] for e in execs], [[2, bid, 0, 70, 2300]])
    check('...buying the stone it lacks', bought, [[2, 4, 70]])
    check('...at the market price', priced, [[2, 4, 70]])
    ai_tick(t + 64 * 10)
    check('...not again before the interval', execs, [])
    ai_tick(t + 2400)
    check('...again after the interval (60 s)', len(execs), 1)
    H.put32(w.WOOD_RES + 8 + p2, 100)
    ai_tick(t + 2 * 2400)
    check('enough stone: nothing bought', (len(execs), bought), (1, []))
    H.put32(w.WOOD_RES + 8 + p2, 0)
    H.put32(w.GOLD_RES + p2, 2000)
    ai_tick(t + 3 * 2400)
    check('not with 2000 gold or less', execs, [])
    H.put32(w.GOLD_RES + p2, 2100)
    prices[4] = 40
    ai_tick(t + 4 * 2400)
    check('cannot pay the stone (2800 gold): no repair', (execs, bought), ([], []))
    prices[4] = 12
    H.put32(w.GOLD_RES + p2, 6000)
    ai_tick(t + 4 * 2400 + 40)
    check('...and it looks again 2 s later, not at once', execs, [])
    ai_tick(t + 4 * 2400 + 80)
    check('...then it repairs', len(execs), 1)
    buy_ok[0] = 0
    ai_tick(t + 6 * 2400)
    check('the market cannot deliver: no repair', execs, [])
    buy_ok[0] = 1
    H.put16(tb + 0x2BE, 20)
    ai_tick(t + 8 * 2400)
    check('the tower burns: the house is next', [e[:4] for e in execs], [[2, 25, 8, 0]])
    check('...buying its wood', bought, [[2, 2, 8]])
    H.put16(tb + 0x2BE, 0)
    enemy[0] = 1
    ai_tick(t + 10 * 2400)
    check('not with enemies near', execs, [])
    enemy[0] = 0
    H.put32(w.AI_TYPES + p2, 0)
    ai_tick(t + 12 * 2400)
    check('not for a human player', execs, [])
    H.put32(w.AI_TYPES + p2, 3)
    H.put16(tb + 0x10C, 85); H.put16(hb + 0x10C, 85)
    ai_tick(t + 14 * 2400)
    check('nothing damaged 20% or more: nothing', execs, [])
    H.put16(tb + 0x10C, 30)
    # the AIC fields
    handler, reset = H.aic['BuildingRepairInterval']
    handler(3, 10)
    check('AIC interval read back', handler(3, None), 10)
    t2 = t + 16 * 2400
    ai_tick(t2)
    check('repairs again', len(execs), 1)
    ai_tick(t2 + 400)
    check('AIC interval 10 s: again after 400 ticks', len(execs), 1)
    gh, gr = H.aic['BuildingRepairMinimumGold']
    gh(3, 7000)
    ai_tick(t2 + 1000)
    check('AIC minimum gold 7000: not with 6000', execs, [])
    gr(3)
    ai_tick(t2 + 1400)
    check('AIC reset: 2000 again', len(execs), 1)
    for a in (price_fn, buy):
        del H.cpu.hooks[a]
    for a in (w.acc, w.rexec, w.ENEMY):
        del H.cpu.hooks[a]


def test_off(ext):
    print(' everything switched off')
    config = {'doors': {'dynamic': False, 'storage': False, 'unstuck': False},
              'firemen': {'spread': False}, 'blacksmith': {'maces': False},
              'repair': {'button': False, 'gold': False, 'fire_blocks': False, 'ai': False},
              'stables': {'breed': False, 'panel': False}, 'farms': {'dairy_scrub': False},
              'hunters': {'tannery': False}}
    H = Host(extreme=ext, config=config)
    br = H.E.find('66 01 9E ? ? ? ? 0F B7 86 ? ? ? ? 66 3D 26 02 7E ?')[0]
    check('only the breeding hook', [a for a, _ in H.patched], [br])


def test_breeding(ext):
    print(' horse breeding time')
    w = W(ext); H = w.H; E = w.E
    site = E.find('66 01 9E ? ? ? ? 0F B7 86 ? ? ? ? 66 3D 26 02 7E ?')[0]
    code = w.jump_target(site)
    breed, wait = site + 20, site + 20 + E.data[E.va2off(site + 19)]
    bid = 5
    b = w.building(bid, 35, 1, 60, 60, 1234)
    knight_horse = w.call_target(w.recruit + 0xE)
    where = []

    def stopper(name):
        def hook(cpu):
            where.append(name)
            cpu.eip = 0x7FFFFFF0
        return hook
    H.cpu.hooks[breed] = stopper('breed')
    H.cpu.hooks[wait] = stopper('wait')

    def ticks_to_breed(t0):
        n = 0
        while True:
            where.clear()
            H.put32(w.TICKS, t0 + n)
            cpu = H.run(code, regs={'esi': bid * 0x32C, 'edi': bid, 'ebx': 1, 'ebp': 0})
            n += 1
            if where == ['breed']:
                check('registers kept', (cpu.r['esi'], cpu.r['edi'], cpu.r['ebx'], cpu.r['ebp']),
                      (bid * 0x32C, bid, 1, 0))
                return n
            assert where == ['wait'] and n < 40000, where
    t = 6400 - bid
    H.put8(b + 0x297, 0)
    check('empty stable: game own time', ticks_to_breed(t), 551)
    H.put8(b + 0x297, 3)
    check('three horses: normal time', ticks_to_breed(t), 551)
    for k, unit in enumerate((20, 21, 22, 23)):
        w.make_unit(unit, 1, 1, 61, 61, 5000 + k)
        H.put8(b + 0x297, 4)
        H.run(knight_horse, regs={'ecx': w.GAMESTATE}, stack=[1, unit])
    check('stall freed for every knight', H.m.read(b + 0x297, 1)[0], 3)
    H.put8(b + 0x297, 1)
    check('5 alive: 9x the time', ticks_to_breed(t), 4951)
    H.put8(b + 0x297, 0)
    check('4 alive (all knights): 3x', ticks_to_breed(t), 1651)
    H.put16(w.unit(20) + 0x8C, 0)            # a knight died
    H.put32(w.unit(21) + 0x98, 99999)        # a knight's slot reused by another unit
    check('2 alive after deaths: normal again', ticks_to_breed(t), 551)
    H.put8(b + 0x297, 3)
    check('5 alive again: 9x', ticks_to_breed(t), 4951)
    H.put8(b + 0x297, 20)
    check('many alive: held at the slowest (10 min)', ticks_to_breed(t), 24001)
    for cfg, horses, want in (({'stables': {'slowdown': False}}, 20, 551),
                              ({'stables': {'breed_seconds': 14}}, 0, 561),
                              ({'stables': {'slowdown_factor': 2, 'normal_horses': 2}}, 3, 2201)):
        w2 = W(ext, config=cfg); H2 = w2.H
        c2 = w2.jump_target(site)
        b2 = w2.building(bid, 35, 1, 60, 60, 1234)
        H2.put8(b2 + 0x297, horses)
        got = []

        def stop2(name):
            def hook(cpu):
                got.append(name)
                cpu.eip = 0x7FFFFFF0
            return hook
        H2.cpu.hooks[breed] = stop2('b')
        H2.cpu.hooks[wait] = stop2('w')
        n = 0
        while True:
            got.clear()
            H2.put32(w2.TICKS, t + n)
            H2.run(c2, regs={'esi': bid * 0x32C, 'edi': bid, 'ebx': 1, 'ebp': 0})
            n += 1
            if got == ['b'] or n > 40000:
                break
        check('config %r' % cfg, n, want)


if __name__ == '__main__':
  for ext in (False, True):
    print('== ' + ('Extreme' if ext else 'Crusader'))
    w = W(ext)
    test_blacksmith(w)
    test_stables(w)
    test_firemen(w)
    test_unstuck(w)
    test_repair_exec(w)
    test_fire_blocks(w)
    test_button(w)
    test_buildings(w)
    test_off(ext)
    test_breeding(ext)
  print('%d checks, %d failed' % (COUNT[0], len(FAILS)))
