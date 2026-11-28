# Changelog

Earlier versions are described in the commit messages (`<version> - <what changed>`).

## 1.0.13 (unreleased)

- **Every option is off by default**, so the module alone plays like the original game. The
  Smarter Buildings Recommended plugin turns the previous defaults back on.
- If the game's instructions that tie a knight to his stable differ from the expected ones,
  stable breeding stays off with a warning; the other options still work. The same holds when
  the breeding timer differs: every stable site is checked before the first stable change.
- The 1.0.12 changes below, which were not released on their own.

## 1.0.12

- **Stables remember their knights after loading a save.** A knight still takes his horse out
  of the stall, but he now stays tied to his stable the way the game itself does it, and the
  game keeps that tie in the save. The stable panel's "in use" number and the breeding
  slowdown count those knights again after a save is loaded or the game is restarted. Before,
  the count lived only in memory, so after a reload a stable showed 0 in use while its knights
  were still alive.
- **One-time gap for older saves:** knights hired with 1.0.11 or earlier, or with a preview
  build of 1.0.12 from before this fix, were not tied to their stable, so they stay uncounted
  for as long as they live. Their stable shows them neither as
  "in use" nor in its breeding slowdown. Knights hired from now on are counted, also after
  reloading.
- New blacksmiths keep the game's sword default; maces are an opt-in setting.
- With "Stables replace horses that knights take" off, the game's own stable behaviour, timer
  and panel stay untouched.
- Module memory (breeding timers, worker retries, hunting and AI repair bookkeeping) is
  cleared when a map or save is loaded, through Map Extensions 1.x.
- Store package: framework, frontend and Map Extensions requirements, tags, expandable
  settings and descriptions in nine languages. Option URLs are unchanged.
