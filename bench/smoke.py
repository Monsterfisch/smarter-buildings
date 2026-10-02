import sys, traceback
from harness import Host
for ext in (False, True):
    try:
        H = Host(extreme=ext)
        print('EXT' if ext else 'VAN', 'ok; scripts', len(H.scripts), 'patched', len(H.patched), 'aic', list(H.aic))
        for l in H.logs: print('  ', l)
    except Exception as e:
        traceback.print_exc()
