"""Dairy farms on thin scrub, tannery carcasses and hunters fetching them - the module's code at its
real hook sites, on both exes."""
import struct
from test_behaviour import W, check, FAILS, COUNT
from harness import MASK, SENTINEL


def run(ext):
    print('== ' + ('Extreme' if ext else 'Crusader'))
    w = W(ext); H = w.H; E = w.E

    # --- dairy farms: the fertile-ground test at the end of checkBuildingCanBePlacedHere
    site = E.find('8B 54 24 48 3B 96 ? ? ? ? 7D 1A 5F C7 86 ? ? ? ? 16 00 00 00 89 8E ? ? ? ? 5E 5D 5B 83 C4 2C C2 14 00 83 7C 24 20 ? 7D')[0] + 0x26
    stub = w.jump_target(site)
    ok_at, fail_at = site + 7 + 0x10, site + 7

    def ground(command, fertile, grass):
        res = []
        H.cpu.hooks[ok_at] = lambda cpu: (res.append('ok'), setattr(cpu, 'eip', SENTINEL))
        H.cpu.hooks[fail_at] = lambda cpu: (res.append('refused'), setattr(cpu, 'eip', SENTINEL))
        # the function's frame: [esp+0x20] fertile tiles, [esp+0x48] tiles of any grass
        stack = [0] * 0x20
        stack[0x20 // 4] = fertile
        stack[0x48 // 4] = grass
        cpu = H.cpu
        cpu.r['esp'] = 0x70100000
        for val in reversed(stack):
            cpu.push(val)
        cpu.r['eax'] = command
        cpu.eip = stub
        cpu.count = 0
        cpu.run(SENTINEL, 10000)
        return res
    check('dairy farm on thin scrub', ground(0x49, 10, 81), ['ok'])
    check('dairy farm on fertile ground', ground(0x49, 81, 81), ['ok'])
    check('dairy farm on too little grass', ground(0x49, 10, 40), ['refused'])
    check('wheat farm on thin scrub still refused', ground(0x46, 10, 81), ['refused'])
    check('wheat farm on fertile ground', ground(0x46, 60, 81), ['ok'])

    # --- tannery carcasses
    tsite = E.find('39 2D ? ? ? ? 0F 84 ? ? ? ? 69 FF 90 04 00 00 89 AF ? ? ? ? 0F BF 87 ? ? ? ? 8B C8 69 C9 2C 03 00 00 8B 91 ? ? ? ? 53 6A 03 6A 03 6A 05')[0] + 0xC
    tstub = w.jump_target(tsite)
    tannery = 30
    w.building(tannery, 16, 2, 120, 120, 3000)
    H.put16(w.bld(tannery) + 0xFE, 119); H.put16(w.bld(tannery) + 0x100, 121)
    tanner = 40
    w.make_unit(tanner, 21, 2, 119, 121, 4000)
    H.put16(w.unit(tanner) + 0x338, tannery)
    body = H.m.read(tstub, 80)
    i = body.find(bytes([0x3B, 0x0C, 0xC5]))      # cmp ecx, [CARCASSES + eax*8 + 4]
    carcasses = struct.unpack('<I', body[i + 3:i + 7])[0] - 4

    def skinned():
        cpu = H.run(tstub, until=tsite + 6, regs={'edi': tanner, 'eax': 0x11, 'ecx': 0x22})
        check('tanner registers kept', (cpu.r['edi'], cpu.r['eax'], cpu.r['ecx']), (tanner * 0x490, 0x11, 0x22))
    for k in range(6):
        skinned()
    check('a carcass per cow, up to 4', H.u32(carcasses + tannery * 8), 4)

    # --- hunters
    hsite = E.find('57 B9 ? ? ? ? E8 ? ? ? ? 0F BF 8D ? ? ? ? 69 C9 90 04 00 00 8B 91 ? ? ? ? 3B 95')[0]
    hstub = w.jump_target(hsite)
    tail = hsite - 5
    post = 31
    w.building(post, 7, 2, 100, 100, 3100)
    H.put16(w.bld(post) + 0xFE, 99); H.put16(w.bld(post) + 0x100, 101)
    hunter = 41
    hu = w.make_unit(hunter, 6, 2, 99, 101, 4100)
    H.put16(hu + 0x338, post)
    dests = []

    def setdest(cpu):
        a = [cpu.m.u32(cpu.r['esp'] + 4 + 4 * k) for k in range(4)]
        dests.append(a)
        cpu.r['eax'] = 1
        cpu.eip = cpu.pop(); cpu.r['esp'] = (cpu.r['esp'] + 0x10) & MASK
    H.cpu.hooks[w.dest] = setdest
    where = []
    H.cpu.hooks[tail] = lambda cpu: (where.append('tail'), setattr(cpu, 'eip', SENTINEL))
    H.cpu.hooks[hsite + 6] = lambda cpu: (where.append('deer search'), setattr(cpu, 'eip', SENTINEL))

    def idle():
        where.clear(); dests.clear()
        H.put16(hu + 0x2C0, 0)
        cpu = H.run(hstub, regs={'edi': hunter, 'esi': hunter * 0x490, 'ebp': post * 0x32C,
                                 'ebx': post, 'ecx': 0x99})
        return cpu

    deer = w.make_unit(50, 44, 0, 150, 150, 5000)
    cpu = idle()
    check('deer left: the game looks for them', where, ['deer search'])
    check('...as it would have', (cpu.r['ecx'], cpu.m.u32(cpu.r['esp'])), (w.US, hunter))
    H.put16(deer + 0x8C, 0)
    idle()
    check('no deer: off to the tannery', (where, dests), (['tail'], [[hunter, 119, 121, 0]]))
    check('...in the walk-to-the-deer state', H.u16(hu + 0x2C0), 0xB)
    check('...bringing the carcasses to his post door', (H.u16(hu + 0x33A), H.u16(hu + 0x33C)), (99, 101))
    check('...his own carcass hand-off', (H.u16(hu + 0x344), H.u32(hu + 0x3A0)), (hunter, 4100))
    check('two carcasses taken', H.u32(carcasses + tannery * 8), 2)
    # back at the post, the first carcass butchered by the game; the second one next
    idle()
    check('second carcass: into the post to butcher', (where, H.u16(hu + 0x2C0), H.u16(hu + 0x2C2)), (['tail'], 0x6D, 3))
    idle()
    check('then the next trip', (where, dests[0][1:3]), (['tail'], [119, 121]))
    check('the tannery is empty', H.u32(carcasses + tannery * 8), 0)
    idle()
    idle()
    check('nothing left: the game as usual', where, ['deer search'])
    # another lord's tannery is not his
    H.put32(carcasses + tannery * 8, 3)
    H.put16(w.bld(tannery) + 0xD6, 3)
    idle()
    check("another lord's tannery: not his", where, ['deer search'])
    H.put16(w.bld(tannery) + 0xD6, 2)
    # a new building in the tannery's slot has no carcasses
    H.put32(w.bld(tannery) + 0xD8, 3999)
    idle()
    check('a rebuilt slot keeps no carcasses', where, ['deer search'])
    for a in (w.dest, tail, hsite + 6):
        del H.cpu.hooks[a]


def run_tiles(ext):
    print('== farm tiles ' + ('Extreme' if ext else 'Crusader'))
    w = W(ext); H = w.H; E = w.E
    site = E.find('83 EC 0C 8B 54 24 18 53 55 56 8B F1 57 8B 7C 24 20')[0]
    tms = E.u32(E.find('F7 04 9D ? ? ? ? 00 01 00 00')[0] + 3) - 0x165160
    layer = tms + 0x1B3FE0
    code = w.jump_target(site)
    seen = []
    H.cpu.hooks[site + 7] = lambda cpu: (seen.append('game'), setattr(cpu, 'eip', SENTINEL))

    def test(tile, command, ground):
        seen.clear()
        H.put8(layer + tile, ground)
        cpu = H.run(code, regs={'ecx': tms}, stack=[tile, 1, command, 0])
        return (cpu.r['eax'] if not seen else 'game'), cpu.r['esp']
    tile = 100 * 400 + 100
    for cmd in (0x46, 0x47, 0x48, 0x49):
        check('farm %X on earth: red' % cmd, test(tile, cmd, 0x00), (1, 0x70100000))
        check('farm %X on iron/stones: red' % cmd, test(tile, cmd, 0x40)[0], 1)
        check('farm %X on thin scrub: the game decides' % cmd, test(tile, cmd, 0x01)[0], 'game')
        check('farm %X on oasis grass: the game decides' % cmd, test(tile, cmd, 0x10)[0], 'game')
        check('farm %X on thick scrub: the game decides' % cmd, test(tile, cmd, 0x80)[0], 'game')
    check('a house on earth: the game decides', test(tile, 0x1E, 0x00)[0], 'game')
    check('a mill on earth: the game decides', test(tile, 0x4A, 0x00)[0], 'game')
    # the game's own test still sees its arguments
    del H.cpu.hooks[site + 7]
    seen.clear()
    H.put8(layer + tile, 0x10)
    cpu = H.run(code, regs={'ecx': tms, 'ebx': 0x11, 'esi': 0x22, 'edi': 0x33, 'ebp': 0x44}, stack=[tile, 1, 0x46, 0])
    check('the game test runs through: stack and registers', (cpu.r['esp'], cpu.r['ebx'], cpu.r['esi'], cpu.r['edi'], cpu.r['ebp']),
          (0x70100000, 0x11, 0x22, 0x33, 0x44))


for ext in (False, True):
    run(ext)
    run_tiles(ext)
print('%d checks, %d failed' % (COUNT[0], len(FAILS)))
