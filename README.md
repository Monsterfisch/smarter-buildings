# Smarter Buildings

## UCP package

Give blocked workers another door to try and add repair controls for more buildings. Separate settings cover fire brigades, farms, hunting, AI repairs and how stables replace horses.

- Module directory: `module/`
- Targets: Stronghold Crusader 1.41 and Stronghold Crusader Extreme 1.41
- Requires UCP framework 3.0.7 and frontend 1.0.2 or a compatible later version
- Requires Map Extensions 1.x for map and save load callbacks


A UCP3 module for Stronghold Crusader and Stronghold Crusader Extreme with fixes and features for
buildings and their workers: doors that move when blocked, stuck workers trying another door, a
Repair button on every building (and AI lords that repair), firemen spreading over several fires,
blacksmiths starting on maces, stables that keep breeding horses (slower the more are alive),
dairy farms on thin scrub, bad farm ground shown red while placing, and hunters that collect stored carcasses from tanneries.

What the module does, in plain English, is in `module/locale/description-en.md`. Every part is a
setting of its own.

## Installing

Download `smarter-buildings-<version>.zip` from the releases and unzip it into
`<game>\ucp\modules`, so you get `ucp\modules\smarter-buildings-<version>`. Then enable it in the
UCP3 GUI. AI character files can set `BuildingRepairInterval` and `BuildingRepairMinimumGold`
(needs the aicloader module).

## Preset tuning

Set these keys under `smarter-buildings` in a preset.

| Key | Default | Effect |
| --- | ---: | --- |
| `repair.x`, `repair.y` | 340, 466 | Repair button position for custom panel layouts |
| `firemen.tiles` | 20 | Distance penalty for assigning a firefighter to a fire already covered |
| `stables.breed_seconds` | 0 | Base replacement time in seconds. 0 uses game timing. |
| `stables.normal_horses` | 4 | Number of horses before breeding slows |
| `stables.slowdown_factor` | 3 | Breeding slowdown factor |
| `stables.slowest_seconds` | 600 | Maximum breeding wait in seconds |
| `hunters.chance` | 50 | Chance of preferring a stored carcass |
| `hunters.carry` | 2 | Carcass capacity per hunter |
| `hunters.stored` | 4 | Carcass capacity per tannery |
| `repair.ai_damage` | 20 | Damage threshold in percent for AI repairs |
| `repair.ai_interval` | 60 | Seconds between AI repair checks |
| `repair.ai_minimum_gold` | 2000 | Minimum gold for AI repairs |

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

## Vanilla and Recommended

Every option of the module is off by default, so the module alone plays like the original
game. Two plugins in this repository form the Smarter Buildings family in the launcher:
`smarter-buildings-recommended` (offered first) switches on the recommended settings, `smarter-buildings-vanilla`
keeps everything off. Plugins that build on the module set the options they need themselves.
