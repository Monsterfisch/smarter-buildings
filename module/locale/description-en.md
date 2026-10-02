# Smarter Buildings

**Author**: Monsterfish
**Version**: 1.0.7

Fixes and improvements for buildings. Every part can be switched on or off in the settings.

## Features

- **Doors that move:** if you build something in front of a house, church, stables, market or
  similar building, its door moves to a free side instead of staying blocked.
- **Granary and armoury doors move too:** goods still get delivered when a wall or gate cuts
  off the old door.
- **Stuck workers find a way out:** a worker who can't reach the stockpile, granary, armoury or
  keep tries the other sides of his building until one works.
- **Firemen spread out:** with several fires, firemen go to different fires instead of all
  running to the same one.
- **Blacksmiths start on maces** instead of swords.
- **Repair any building:** damaged buildings get the Repair button towers have. A repair costs
  the part of the building's price that was destroyed, gold included. Pointing at the button
  shows the cost. You can't repair while the building burns or enemies are near.
- **AI lords repair too:** they check their buildings and fix the most damaged one (at least
  20% damaged) when they have enough gold, buying any wood and stone they lack at the market.
- **Stables keep breeding:** when a knight takes a horse, the stable breeds a new one. The more
  of a stable's horses are alive, the slower the next one comes, but it never stops. The stable
  panel shows how many of its horses are ridden by living knights, and a bar shows how close
  the next horse is.
- **Dairy farms on thin scrub:** dairy farms can also be built on thin scrub, not only on thick
  scrub and oasis grass.
- **Meat from tanneries:** every cow a tanner skins leaves a carcass at the tannery. Once all the
  deer are gone, hunters fetch up to 2 carcasses at a time, butcher them at their hunting post
  and take the meat to the granary.

## AIC settings

These go in an AI character file and need the aicloader module. Without them every AI uses
the values from the module's settings.

| Setting | What it does |
| --- | --- |
| `BuildingRepairInterval` | Seconds the AI waits between two repairs (default 60). |
| `BuildingRepairMinimumGold` | The AI only repairs while it has more gold than this (default 2000). |
