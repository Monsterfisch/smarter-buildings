# Smarter Buildings

A UCP3 module for Stronghold Crusader and Stronghold Crusader Extreme with fixes and features for
buildings and their workers: doors that move when blocked, stuck workers trying another door, a
Repair button on every building (and AI lords that repair), firemen spreading over several fires,
blacksmiths starting on maces, stables that keep breeding horses (slower the more are alive),
dairy farms on thin scrub, bad farm ground shown red while placing, and hunters fetching carcasses from tanneries once the deer are gone.

What the module does, in plain English, is in `module/locale/description-en.md`. Every part is a
setting of its own.

## Installing

Download `smarter-buildings-<version>.zip` from the releases and unzip it into
`<game>\ucp\modules`, so you get `ucp\modules\smarter-buildings-<version>`. Then enable it in the
UCP3 GUI. AI character files can set `BuildingRepairInterval` and `BuildingRepairMinimumGold`
(needs the aicloader module).

## What is in here

| Folder | |
|---|---|
| `module/` | the module itself - this is the source of truth, edited in place |
| `bench/` | the emulator bench: the module's own Lua runs against the real exe image, its assembly is assembled with UCP's own fasm.dll and then executed, together with the game's own functions where practical |
| `tools/publish.py` | copies `module/` into the game's module folder under a new version |

## Working on it

1. Edit under `module/`.
2. Run the bench until it is green, on both executables:
   * `python bench/test_behaviour.py` - doors, stuck workers, firemen, stables and breeding, the
     repair command, the Repair button, AI repairs, everything switched off
   * `python bench/test_tooltip.py` - Repair button places per panel, the repair cost text and its
     gold part, the cost line's layer
   * `python bench/test_stable_panel.py` - the stable panel's "in use" number and next-horse bar
   * `python bench/test_food.py` - dairy farms on thin scrub, farm tiles shown red, tannery carcasses, hunters
3. `python tools/publish.py --bump` - raises the last version slot and copies the module to
   `ucp/modules/smarter-buildings-<version>`, leaving the build before it installed and clearing
   anything older. Do this with the game closed.
4. In the UCP GUI press F5, then apply.
5. Commit and tag: `git commit -am "<version> - <what changed>" && git tag v<version>`.

The bench needs Python with `lupa`, `capstone`, `pefile` and `keystone-engine`, and a 32-bit
PowerShell for fasm.dll; it reads the executables from the game folder named in `bench/shc.py`.

Every address is found by pattern scan or read from the instruction that uses it, so the module
runs on `Stronghold Crusader.exe` and `Stronghold_Crusader_Extreme.exe` alike.
