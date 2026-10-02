--[[
  Smarter Buildings

  Seven changes to buildings, each a setting of its own:

  1. Doors that move. Houses, chapels, churches, cathedrals, stables, dog cages and the market
     get their door checked every 64 ticks with the game's own buildingIsAccessible, which
     moves a door that is blocked or cut off. The game only does that for buildings whose
     workers ask for it; these never do, so their door stayed where it was placed.
  2. Deliveries past gates. The granary's and the armoury's doors are checked the same way,
     and a worker who cannot reach them from his workshop gets his workshop's door moved (3).
  3. Stuck workers. When a worker standing on his workplace's door finds no way to where he
     has to go, the door is walked clockwise round the building (the game's own door search,
     started one step further each time); the worker is put on each new door and asked
     again. The first door that works stays; if none does, door and worker go back.
  4. Firemen spread out: a fire that other firemen already head for looks further away to
     the next one, so several fires get a fireman each.
  5. The blacksmith starts on maces instead of swords.
  6. A Repair button for every damaged building, the game's own (towers and gates have it
     already): it costs the share of the building's price that the damage is, gold
     included, and is greyed out while the building burns or enemies are near. AI lords
     repair too, once per interval (AIC field BuildingRepairInterval) while they have more
     gold than BuildingRepairMinimumGold.
  7. A knight takes his horse away with him: the stall is free at once and the stable breeds
     a new horse, instead of keeping the stall for as long as the knight lives.

  Every address is found by pattern scan or read out of the instruction that uses it, so the
  module runs on Stronghold Crusader.exe and Stronghold_Crusader_Extreme.exe alike.
]]

local templates = require("templates")

local MODULE_NAME = "smarter-buildings"

local DEFAULTS = {
  doors = { dynamic = true, storage = true, unstuck = true },
  firemen = { spread = true, tiles = 20 },
  blacksmith = { maces = true },
  repair = { button = true, gold = true, fire_blocks = true, x = 340, y = 466,
    ai = true, ai_interval = 60, ai_minimum_gold = 2000, ai_damage = 20 },
  farms = { dairy_scrub = true },
  hunters = { tannery = true, carry = 2, stored = 4 },
  stables = { breed = true, panel = true, breed_seconds = 0, slowdown = true, normal_horses = 4,
    slowdown_factor = 3, slowest_seconds = 600 },
}

---------------------------------------------------------------------------------------
-- What the game's code looks like where this module touches it
---------------------------------------------------------------------------------------

-- setupBuildingData: a new blacksmith gets swords (0x16) when swords can be made, maces
-- (0x15) otherwise. The two immediates are made 0x15.
local AOB_BLACKSMITH = "83 3D ? ? ? ? 00 8D 84 37 ? ? ? ? 8D 8C 37 ? ? ? ? 74 0C 66 C7 00 16 00 66 "
  .. "C7 01 16 00"
local BLACKSMITH_SWORDS = { 0x1A, 0x1F }

-- euroRecruit, where a new knight is tied to a stable: call linkageBetweenHorseUnitAndStable.
local AOB_KNIGHT_HORSE = "83 7C 24 18 FF 75 25 55 57 B9 ? ? ? ? E8 ? ? ? ? 66 89 86"
local KNIGHT_HORSE_CALL = 0x0E
local AOB_HORSE_LINKAGE = "53 8B 1D ? ? ? ? 55 56 BE 01 00 00 00 3B DE 57 8B E9"
local LINKAGE_SLOTS = { 0x8B, { 0x8D, 0x91 } }   -- lea edx, [ecx + buildings + insideUnitID]
local BUILDING_INSIDE_UNITS = 0x2E0
-- UpdateStables: a stable with fewer than four horses counts up (building +0x29A, a word, once a
-- tick) and gets a horse when the count passes 550 (about 14 s at normal speed):
-- add word [esi+counter],bx / movzx eax,word [esi+counter] / cmp ax,0x226 / jle wait.
local AOB_HORSE_BREEDING = "66 01 9E ? ? ? ? 0F B7 86 ? ? ? ? 66 3D 26 02 7E ?"
local HORSE_BREEDING_SIZE = 20
local HORSE_BREEDING_TIME = 16                -- the immediate of cmp ax, 0x226
local ORIGIN_SLOTS = 10000               -- unit slots remembered (12 bytes each)
-- RenderBuildingMenu_Stables: "n horses available" / "n in use".
local AOB_STABLE_PANEL = "A1 ? ? ? ? 8B 0D ? ? ? ? 56 8B 35 ? ? ? ? 6A 00 6A 00 6A 10 6A 00 6A 00 05 D3 01 "
  .. "00 00 50 83 C1 19 51 6A 00 6A 35"
local STABLE_PANEL_ENTRY = 5                     -- mov eax, [panel y]
local STABLE_PANEL_X = { 0x05, { 0x8B, 0x0D } }
local STABLE_IN_USE = 0xE8                       -- movsx edx, byte [esi + stalls kept]
local STABLE_IN_USE_SIZE = 7
local STABLE_IN_USE_TEST = 0x111                 -- cmp byte [esi + stalls kept], 1
-- RenderBuildingMenu_RenderTowerAndGateHealth: the health bar's colours and pencil.
local AOB_HEALTH_BAR = "83 EC 20 A1 ? ? ? ? 33 C4 89 44 24 1C 8B 0D ? ? ? ? 66 8B 15 ? ? ? ? 69 C9 2C 03 00 00"
local HEALTH_BAR = {
  lime = { 0x14, { 0x66, 0x8B, 0x15 } },
  black = { 0x5A, { 0x0F, 0xB7, 0x15 } },
  pencil = { 0x7E, { 0xB9 } },
  red = { 0x88, { 0x0F, 0xB7, 0x15 } },
}
local HEALTH_BAR_BORDER = 0x83                   -- call drawBorderBox
local HEALTH_BAR_BOX = 0xA9                      -- call drawColorBox
local BAR_PLACE = { 0xAF, 0x231 }                -- under the two horse lines, from the panel
local BAR_WIDTH = 50                             -- as the towers' health bar

-- findClosestReachableAlliedBuilding (the firemen's fire search).
local AOB_FIRE_SEARCH = "83 EC 08 53 55 57 8B 7C 24 18 69 FF 90 04 00 00 8B 87 ? ? ? ? 8B E9"
local FIRE_UNIT_TILE = { 0x10, { 0x8B, 0x87 } }     -- mov eax, [edi + units + tile]
local FIRE_HOOK = 0xB3                              -- mov eax,[esp+0x10] / cmp [distance],eax
local FIRE_HOOK_SIZE = 10
local FIRE_DISTANCE = { 0xB7, { 0x39, 0x05 } }
local FIREMAN = 53

-- updateBuildings, right after the call to a building's own update.
local AOB_BUILDING_UPDATE = "0F BF 80 E6 00 00 00 8B 0C 85 ? ? ? ? FF D1 8B 0D ? ? ? ?"
local BUILDING_UPDATE_HOOK = 0x10                   -- mov ecx, [current building]
local BUILDING_UPDATE_SIZE = 6

-- BuildingsState::buildingIsAccessible(building, flag): the door check.
local AOB_IS_ACCESSIBLE = "83 EC 0C 8B 44 24 10 85 C0 57 8B F9 89 7C 24 04 7F 09"
local ACCESSIBLE_AREAS = { 0x3D, { 0x0F, 0xBF, 0x14, 0x4D } }
local ACCESSIBLE_ROWS = { 0x5A, { 0x8B, 0x14, 0x85 } }
local ACCESSIBLE_HEIGHTS = { 0x61, { 0x0F, 0xB6, 0x84, 0x0A } }
local ACCESSIBLE_PATHFINDING = { 0x11E, { 0xB9 } }

-- UnitsState::setDestinationForUnit(unit, x, y, mode). ucp2-legacy's ladder fix patches it
-- from +9, so the pattern skips those bytes; this module takes the first 7.
local AOB_SET_DESTINATION = "83 EC 08 8B 44 24 0C 8B D0 ? ? ? ? ? ? 53 55 8B 6C 24 18 56 8D 34 0A"
local SET_DESTINATION_SIZE = 7
local AOB_SET_POSITION = "53 8B 5C 24 0C 81 FB 8F 01 00 00 55 8B E9 0F 87"
local AOB_DETERMINE_DOOR = "83 EC 2C 53 55 8B 6C 24 38 69 ED 2C 03 00 00 56 8B F1"

-- The tower and gate Repair button: its action, its drawing, the command it sends, and the
-- cost calculation.
local AOB_REPAIR_ACTION = "A1 ? ? ? ? 56 57 50 B9 ? ? ? ? 33 FF E8 ? ? ? ? 85 C0 75 03 8D 78 01"
local REPAIR_ACTION = {
  selected = { 0x00, { 0xA1 } },
  buildingsState = { 0x08, { 0xB9 } },
  gameMode = { 0x1B, { 0xA1 } },
  localPlayer = { 0x7A, { 0xA1 } },
  woodCost = { 0x7F, { 0x8B, 0x15 } },
  stoneCost = { 0xA4, { 0x8B, 0x0D } },
}
local REPAIR_ACTION_ENEMY_CALL = 0x54
local AOB_REPAIR_RENDER = "A1 ? ? ? ? 56 8B F0 69 F6 2C 03 00 00 0F BF 8E ? ? ? ? 57 33 FF 3B 0D"
local REPAIR_RENDER = {
  disabled = { 0x1E, { 0x89, 0x3D } },
  hover = { 0x85, { 0xC7, 0x05 } },
  buttonW = { 0xCA, { 0xA1 } },
  buttonY = { 0xCF, { 0x8B, 0x0D } },
  buttonX = { 0xDF, { 0x03, 0x05 } },
}
local REPAIR_RENDER_ENEMY_CALL = 0x6F
local AOB_REPAIR_EXEC = "8B 44 24 08 57 8B F8 69 FF 2C 03 00 00 8B 8F ? ? ? ? 3B 4C 24 18"
local REPAIR_EXEC_SIZE = 7
local REPAIR_EXEC_WOOD = { 0x39, { 0x3B, 0x88 } }   -- player resources: wood
local REPAIR_EXEC_STONE = { 0x5F, { 0x3B, 0x98 } }  -- player resources: stone
local REPAIR_EXEC_LOSS = 0x9A                       -- call processResourceLoss
local AOB_REPAIR_COST = "51 8B 44 24 08 69 C0 2C 03 00 00 55 8B E9 0F B7 94 28"
local REPAIR_COST_TABLE = { 0x47, { 0x8B, 0xB8 } }  -- building costs: wood, stone, iron, pitch, gold
local RESOURCE_GOLD_FROM_WOOD = (15 - 2) * 4
local REPAIR_W = 100
local REPAIR_H = 28

-- Where the Repair button goes on a panel, by the panel's tab (the game picks the tab from the
-- building type in openBuildingStatusMenuForBuildingID): moved from the default place (move) or
-- put somewhere else entirely (absolute), wherever the panel has its own controls there.
local TAB_COUNT = 128
local PANEL_PLACES = {
  [4] = { move = { -130, 0 } },          -- granary: left of the ration buttons
  [3] = { move = { 50, 0 } },            -- inn
  [23] = { move = { 80, 0 } },           -- engineer's guild
  [24] = { move = { 80, 0 } },           -- tunneler's guild
  [44] = { absolute = { 230, 562 } },    -- mercenary post: middle, at the bottom
  [1] = { absolute = { 230, 422 } },     -- barracks: middle, on the stone under the crenellations
}
-- Panels whose own items (the recruit portraits) would cover the button: it is drawn from their
-- own bottom text line, which comes after the portraits. (The crenellations themselves are
-- see-through parts of the panel picture; a button there shows magenta.)
local LATE_TABS = { 1, 44 }
local LATE_LINE = { 20, 424 }           -- the barracks' and mercenary post's own bottom text line

-- renderConstructionMenu: the hover help of the hovered item (item +0x2C indexes a table of
-- { kind, text group, text, value }); kind 8 is the repair cost line. The game only shows it on
-- a few panels, and only with its help texts switched on.
local AOB_HOVER_HELP = "55 56 57 8B F1 FF 15 ? ? ? ? 8B 7E 38 33 ED 3B FD 0F 84 ? ? ? ? 8B 4F 2C 81 "
  .. "E1 FF FF 00 00"
local HOVER_HELP = {
  table = { 0x58, { 0x8B, 0x91 } },
  bubbleHelp = { 0x236, { 0x39, 0x2D } },
  setText = 0x262,                      -- call setBottomLeftTextDisplayText
}
local ITEM_HELP = 0x2C
local HELP_REPAIR_COST = 8
-- renderCurrentlyDisplayedTextConstructionCost, around the repair cost line (kind 8).
local AOB_COST_TEXT = "8B 15 ? ? ? ? 83 EC 0C 83 7C 24 10 00 53 8B 1D ? ? ? ? 56 8B F1 75 17 83 FB 10 "
  .. "75 12 83 FA 01 0F 84 ? ? ? ?"
local COST_TEXT = {
  number = 0x1083,                      -- call renderNumber2
  textureCore = { 0x10A6, { 0xB9 } },
  picture = 0x10AB,                     -- call renderGM
  open = { 0x10CF, { 0x68 } },          -- "("
  textManager = { 0x10D4, { 0xB9 } },
  text = 0x10D9,                        -- call renderInGameTextWithShadow
  close = { 0x1139, { 0x68 } },         -- ")"
  surface = { 0x1243, { 0xC7, 0x05 } },
  drawBuffer = { 0x124D, { 0xC7, 0x05 } },
}
local COST_TEXT_COLOUR = 0xB8EEFB
local COST_TEXT_LAYER = 0x3B            -- cmp eax,6 / push edi / je <screen layer>
local COST_TEXT_LAYER_SIZE = 6
local GOLD_ICON = 0x7C                  -- the gold coin among the cost pictures (gm 0x2E)

-- Other places addresses are read from.
local AOB_TICK_COUNTER = "8B 87 50 0A 00 00 8B 8F 98 09 00 00 8B 15 ? ? ? ?"
local TICK_COUNTER_OPERAND = 14
local AOB_MENU_ITEM = "8B 56 10 8B 46 4C 8B 4E 0C 52 8B 50 08 03 56 08 8B 40 04 03 46 04 51 52 50 "
  .. "B9 ? ? ? ? E8"
local MENU_ITEM_MOUSE = { 0x19, { 0xB9 } }
local MENU_ITEM_IS_INSIDE = 0x1E
local MOUSE_LEFT_CLICK = 0x34
local AOB_KEY_GUARD = "F7 C1 00 00 00 40 0F 85 ? ? ? ? B9 ? ? ? ? E8 ? ? ? ? 85 C0 0F 84 ? ? ? ? 83 3D "
  .. "? ? ? ? FF"
local KEY_GUARD_SCREEN = { 0x0C, { 0xB9 } }
local SCREEN_MENU_TAB = 0x10
local SCREEN_ID = 0x0C
local AOB_AI_TYPES = "69 C0 F4 39 00 00 8B 88 ? ? ? ? 69 C9 A4 02 00 00"
local AI_TYPES_OPERAND = { 0x06, { 0x8B, 0x88 } }

-- MenuItem layout (0x50 bytes).
local ITEM_SIZE = 0x50
local ITEM_TYPE = 0x00
local ITEM_X = 0x04
local ITEM_Y = 0x08
local ITEM_ACTION = 0x14
local ITEM_RENDER = 0x1C
local TYPE_BLOCK = 0x64
local TYPE_LAST = 0x66
local TYPE_EVERY_FRAME = 0x00
local STATUS_LINE = { 25, 570 }     -- the shared "workers" status line every building shows
local TEXT_LINE = { 20, 415 }       -- the shared bottom text line (costs, help texts)

-- Building types (OpenSHC's BuildingType).
local TYPE_COUNT = 110
local DOOR_TYPES = { 1, 2, 26, 35, 36, 37, 38, 99 }   -- hovel, house, market, stables, chapel,
                                                      -- church, cathedral, dog cage
local STORAGE_TYPES = { 11, 19 }                      -- armoury, granary
-- Unit types that work in a building (OpenSHC's UnitType).
local UNIT_TYPE_COUNT = 80
local WORKER_TYPES = { 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 31, 32, 36 }
local RETRY_TICKS = 200             -- a building's door is walked round at most every 5 s
local MAX_TRIES = 64

local TICKS_PER_SECOND = 40         -- at normal game speed
local AI_SLOTS = 17                 -- AI characters are numbered 1..16
local AIC_INTERVAL = "BuildingRepairInterval"
local AIC_MINIMUM_GOLD = "BuildingRepairMinimumGold"
-- BuildingsState: the number of building slots in use.
local BUILDINGS_IN_USE = 8
-- buyGoods(player, resource, amount): what the AI buys at the market with; it calls
-- getBuyPrice(player, resource, amount) on GameState first.
local AOB_BUY_GOODS = "53 8B 5C 24 10 55 8B 6C 24 10 56 8B 74 24 10 57 53 55 56 B9 ? ? ? ? E8 ? ? ? ? 53 55 56 B9"
local BUY_GOODS_GAME_STATE = { 0x13, { 0xB9 } }
local BUY_GOODS_PRICE = 0x18
local AI_RETRY_TICKS = 80             -- an AI lord with nothing to repair looks again 2 s later

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function scan(pattern, purpose)
  local ok, address = pcall(core.AOBScan, pattern)
  if not ok or address == nil then
    error(MODULE_NAME .. ": could not find " .. purpose)
  end
  return address
end

local function expectBytes(address, bytes, purpose)
  for index, byte in ipairs(bytes) do
    if (core.readByte(address + index - 1) & 0xFF) ~= byte then
      error(string.format("%s: %s at 0x%X is not the code this module knows", MODULE_NAME, purpose,
        address))
    end
  end
end

local function readOperand(base, site, purpose)
  expectBytes(base + site[1], site[2], purpose)
  return core.readInteger(base + site[1] + #site[2])
end

local function readCallTarget(base, offset, purpose)
  expectBytes(base + offset, { 0xE8 }, purpose)
  return base + offset + 5 + core.readInteger(base + offset + 1)
end

local function redirectCall(base, offset, target, purpose)
  expectBytes(base + offset, { 0xE8 }, purpose)
  core.writeCode(base + offset, { 0xE8, core.itob(core.getRelativeAddress(base + offset, target, -5)) })
end

-- FASM gets a fixed 64 KB for source, symbols and output: only pass what a script uses.
local function assemble(script, values)
  local used = {}
  for name, value in pairs(values) do
    if script:find("%f[%w_]" .. name .. "%f[^%w_]") then
      used[name] = value
    end
  end
  return core.allocateAssembly(script, used)
end

local function jumpTo(address, target, size)
  local code = { 0xE9, core.itob(core.getRelativeAddress(address, target, -5)) }
  for _ = 6, size do
    code[#code + 1] = 0x90
  end
  core.writeCode(address, code)
end

local function setting(config, group, name)
  local section = config[group]
  if type(section) == "table" and section[name] ~= nil then
    return section[name]
  end
  return DEFAULTS[group][name]
end

local function number(config, group, name, low, high)
  local value = tonumber(setting(config, group, name)) or DEFAULTS[group][name]
  value = math.tointeger(math.floor(value)) or DEFAULTS[group][name]
  return math.max(low, math.min(high, value))
end

local function byteTable(size, entries)
  local address = core.allocate(size, true)
  for _, index in ipairs(entries) do
    core.writeByte(address + index, 1)
  end
  return address
end

local function patternOf(...)
  local bytes = {}
  for _, value in ipairs({ ... }) do
    for _, byte in ipairs(core.itob(value)) do
      bytes[#bytes + 1] = string.format("%02X", byte & 0xFF)
    end
  end
  return table.concat(bytes, " ")
end

---------------------------------------------------------------------------------------
-- The parts
---------------------------------------------------------------------------------------

local function patchBlacksmith()
  local site = scan(AOB_BLACKSMITH, "the new blacksmith's weapon")
  for _, offset in ipairs(BLACKSMITH_SWORDS) do
    expectBytes(site + offset, { 0x16 }, "the new blacksmith's weapon")
    core.writeCode(site + offset, { 0x15 })
  end
end

local function patchStables(v)
  local site = scan(AOB_KNIGHT_HORSE, "where a knight takes a horse")
  local linkage = scan(AOB_HORSE_LINKAGE, "the stable's horses")
  if readCallTarget(site, KNIGHT_HORSE_CALL, "where a knight takes a horse") ~= linkage then
    error(MODULE_NAME .. ": the knight's horse is not taken the way this module knows")
  end
  local slots = readOperand(linkage, LINKAGE_SLOTS, "the stable's horses")
  if slots - BUILDING_INSIDE_UNITS ~= v.BUILDINGS then
    error(MODULE_NAME .. ": the building layout is not the one this module knows")
  end
  local wrapper = assemble(templates.stables, { LINKAGE = linkage, BUILDINGS = v.BUILDINGS,
    UNITS = v.UNITS, ORIGINS = v.ORIGINS, ORIGIN_SLOTS = ORIGIN_SLOTS })
  redirectCall(site, KNIGHT_HORSE_CALL, wrapper, "where a knight takes a horse")
end

local function patchHorseBreeding(v, config, panel)
  local site = scan(AOB_HORSE_BREEDING, "the stable's horse breeding")
  local jump = site + HORSE_BREEDING_SIZE - 2
  expectBytes(jump, { 0x7E }, "the stable's horse breeding")
  -- 0 = the game's own breeding time: the immediate this hook replaces (550 ticks unless the exe
  -- was changed).
  local seconds = number(config, "stables", "breed_seconds", 0, 3600)
  local base = seconds * TICKS_PER_SECOND
  if seconds == 0 then
    base = (core.readByte(site + HORSE_BREEDING_TIME) & 0xFF)
      | ((core.readByte(site + HORSE_BREEDING_TIME + 1) & 0xFF) << 8)
  end
  local slowdown = setting(config, "stables", "slowdown")
  local data = core.allocate(16 + 2000 * 8, true)
  local h = {
    BASE = data,
    NORMAL = data + 4,
    FACTOR = data + 8,
    SLOWEST = data + 12,
    KNIGHTS = data + 16,
    COUNTERS = data + 16 + 2000 * 4,
    ORIGINS = v.ORIGINS,
    ORIGIN_SLOTS = ORIGIN_SLOTS,
    UNITS = v.UNITS,
    UNITS_STATE = v.UNITS - 0x614,
    BUILDINGS = v.BUILDINGS,
    TICKS = v.TICKS,
    BREED_NOW = site + HORSE_BREEDING_SIZE,
    BREED_LATER = site + HORSE_BREEDING_SIZE + (core.readByte(jump + 1) & 0xFF),
  }
  core.writeInteger(h.BASE, base)
  core.writeInteger(h.NORMAL, slowdown and number(config, "stables", "normal_horses", 1, 100) or 1000000)
  core.writeInteger(h.FACTOR, number(config, "stables", "slowdown_factor", 1, 10))
  core.writeInteger(h.SLOWEST, math.max(base, number(config, "stables", "slowest_seconds", 1, 7200)
    * TICKS_PER_SECOND))
  h.COUNT_KNIGHTS = assemble(templates.countKnights, h)
  h.BREED_LIMIT = assemble(templates.breedLimit, h)
  jumpTo(site, assemble(templates.breeding, h), HORSE_BREEDING_SIZE)
  if panel then
    local ok, message = pcall(function()
      local stable = scan(AOB_STABLE_PANEL, "the stable panel")
      local bar = scan(AOB_HEALTH_BAR, "the tower health bar")
      expectBytes(stable + STABLE_IN_USE, { 0x0F, 0xBE, 0x96 }, "the stable panel")
      expectBytes(stable + STABLE_IN_USE_TEST, { 0x80, 0xBE }, "the stable panel")
      expectBytes(stable + STABLE_IN_USE_TEST + 6, { 0x01 }, "the stable panel")
      local u = {
        SELECTED = v.SELECTED,
        COUNT_KNIGHTS = h.COUNT_KNIGHTS,
        STALLS_KEPT = core.readInteger(stable + STABLE_IN_USE + 3),
        IN_USE = core.allocate(4, true),
        IN_USE_RESUME = stable + STABLE_IN_USE + STABLE_IN_USE_SIZE,
      }
      local inUse = assemble(templates.stableInUse, u)
      local p = {
        SELECTED = v.SELECTED,
        BUILDINGS = v.BUILDINGS,
        BREED_LIMIT = h.BREED_LIMIT,
        COUNTERS = h.COUNTERS,
        MENU_Y = core.readInteger(stable + 1),
        MENU_X = readOperand(stable, STABLE_PANEL_X, "the panel's place"),
        BAR = core.allocate(8, true),
        BAR_X = BAR_PLACE[1],
        BAR_Y = BAR_PLACE[2],
        BAR_WIDTH = BAR_WIDTH,
        LIME = readOperand(bar, HEALTH_BAR.lime, "the health bar colours"),
        BLACK = readOperand(bar, HEALTH_BAR.black, "the health bar colours"),
        RED = readOperand(bar, HEALTH_BAR.red, "the health bar colours"),
        PENCIL = readOperand(bar, HEALTH_BAR.pencil, "the health bar drawing"),
        BORDER_BOX = readCallTarget(bar, HEALTH_BAR_BORDER, "the health bar drawing"),
        COLOUR_BOX = readCallTarget(bar, HEALTH_BAR_BOX, "the health bar drawing"),
        PANEL_RESUME = stable + STABLE_PANEL_ENTRY,
      }
      expectBytes(stable, { 0xA1 }, "the stable panel")
      local wrapper = assemble(templates.stablePanel, p)
      jumpTo(stable + STABLE_IN_USE, inUse, STABLE_IN_USE_SIZE)
      core.writeCode(stable + STABLE_IN_USE_TEST, { 0x83, 0x3D, core.itob(u.IN_USE), 0x01 })
      jumpTo(stable, wrapper, STABLE_PANEL_ENTRY)
    end)
    if not ok then
      log(WARNING, MODULE_NAME .. ": the stable panel shows the game's own numbers: " .. tostring(message))
    end
  end
end

-- checkBuildingCanBePlacedHere: a farm needs grass under every tile and at least 50 tiles of
-- oasis grass or thick scrub (cmp dword [esp+0x20],0x32 / jge).
local AOB_FARM_GROUND = "8B 54 24 48 3B 96 ? ? ? ? 7D 1A 5F C7 86 ? ? ? ? 16 00 00 00 89 8E ? ? ? ? 5E 5D 5B "
  .. "83 C4 2C C2 14 00 83 7C 24 20 ? 7D"
local FARM_GROUND_HOOK = 0x26
local FARM_GROUND_SIZE = 5
local DAIRY_COMMAND = 0x49              -- M_MAPPER_CATTLEFARM
-- UpdateTanner, the end of skinning a cow: imul edi,edi,0x490 (6 bytes).
local AOB_TANNER_SKINNED = "39 2D ? ? ? ? 0F 84 ? ? ? ? 69 FF 90 04 00 00 89 AF ? ? ? ? 0F BF 87 ? ? ? ? 8B C8 "
  .. "69 C9 2C 03 00 00 8B 91 ? ? ? ? 53 6A 03 6A 03 6A 05"
local TANNER_HOOK = 0x0C
local TANNER_HOOK_SIZE = 6
-- UpdateHunter, state 0, where the hunter looks for deer: push edi / mov ecx,UnitsState / call
-- findNearestShootableDeer. The function's epilogue sits right before it.
local AOB_HUNTER_DEER = "57 B9 ? ? ? ? E8 ? ? ? ? 0F BF 8D ? ? ? ? 69 C9 90 04 00 00 8B 91 ? ? ? ? 3B 95"
local HUNTER_HOOK_SIZE = 6
local HUNTER_TAIL = -5                  -- pop edi / esi / ebp / ebx / ret
local DEER = 44                         -- UT_ANTELOPESHDEER
local TANNERY = 16                      -- BT_TANNER
local HUNTER_SLOTS = 10000

local function patchDairyGround()
  local site = scan(AOB_FARM_GROUND, "the farm ground test") + FARM_GROUND_HOOK
  expectBytes(site, { 0x83, 0x7C, 0x24, 0x20 }, "the farm ground test")
  local code = assemble(templates.dairyGround, {
    DAIRY_COMMAND = DAIRY_COMMAND,
    FERTILE_TILES = core.readByte(site + 4) & 0xFF,
    GROUND_RESUME = site + FARM_GROUND_SIZE,
  })
  jumpTo(site, code, FARM_GROUND_SIZE)
end

local function patchHunters(v, config)
  local tanner = scan(AOB_TANNER_SKINNED, "where a tanner finishes a cow") + TANNER_HOOK
  local hunter = scan(AOB_HUNTER_DEER, "where a hunter looks for deer")
  expectBytes(tanner, { 0x69, 0xFF, 0x90, 0x04, 0x00, 0x00 }, "where a tanner finishes a cow")
  expectBytes(hunter + HUNTER_TAIL, { 0x5F, 0x5E, 0x5D, 0x5B, 0xC3 }, "the hunter's update")
  if core.readInteger(hunter + 2) ~= v.UNITS - 0x614 then
    error(MODULE_NAME .. ": the hunter's update is not the one this module knows")
  end
  local h = {
    CARCASSES = core.allocate(2000 * 8, true),
    EXTRA = core.allocate(HUNTER_SLOTS * 8, true),
    UNIT_SLOTS = HUNTER_SLOTS,
    STORED_MAX = number(config, "hunters", "stored", 1, 100),
    CARRY = number(config, "hunters", "carry", 1, 10),
    UNITS = v.UNITS,
    UNITS_STATE = v.UNITS - 0x614,
    BUILDINGS = v.BUILDINGS,
    BUILDINGS_STATE = v.BUILDINGS_STATE,
    DEER = DEER,
    TANNERY = TANNERY,
    SET_DESTINATION = scan(AOB_SET_DESTINATION, "the unit route search"),
    TANNER_RESUME = tanner + TANNER_HOOK_SIZE,
    HUNTER_TAIL = hunter + HUNTER_TAIL,
    HUNTER_RESUME = hunter + HUNTER_HOOK_SIZE,
  }
  local carcass = assemble(templates.tannerCarcass, h)
  local hunt = assemble(templates.hunterTannery, h)
  jumpTo(tanner, carcass, TANNER_HOOK_SIZE)
  jumpTo(hunter, hunt, HUNTER_HOOK_SIZE)
end

local function patchFiremen(v, tiles)
  local search = scan(AOB_FIRE_SEARCH, "the firemen's fire search")
  local units = readOperand(search, FIRE_UNIT_TILE, "the firemen's fire search") - 0xD4
  if units ~= v.UNITS then
    error(MODULE_NAME .. ": the unit layout is not the one this module knows")
  end
  expectBytes(search + FIRE_HOOK, { 0x8B, 0x44, 0x24, 0x10 }, "the firemen's fire search")
  local code = assemble(templates.firemen, {
    UNITS = v.UNITS,
    UNITS_STATE = v.UNITS - 0x614,
    FIREMAN = FIREMAN,
    PENALTY = tiles,
    DISTANCE = readOperand(search, FIRE_DISTANCE, "the fire distance"),
    RESUME = search + FIRE_HOOK + FIRE_HOOK_SIZE,
  })
  jumpTo(search + FIRE_HOOK, code, FIRE_HOOK_SIZE)
end

local function patchUnstuck(v)
  local destination = scan(AOB_SET_DESTINATION, "the unit route search")
  expectBytes(destination, { 0x83, 0xEC, 0x08, 0x8B, 0x44, 0x24, 0x0C }, "the unit route search")
  local data = core.allocate(16 + 2000 * 4, true)
  local w = {
    BUSY = data,
    UNITS_THIS = data + 4,
    TRIED = data + 16,
    TICKS = v.TICKS,
    UNITS = v.UNITS,
    BUILDINGS = v.BUILDINGS,
    BUILDINGS_STATE = v.BUILDINGS_STATE,
    UNIT_TYPE_COUNT = UNIT_TYPE_COUNT,
    WORKER_TYPES = byteTable(UNIT_TYPE_COUNT, WORKER_TYPES),
    RETRY_TICKS = RETRY_TICKS,
    MAX_TRIES = MAX_TRIES,
    ROWS = v.ROWS,
    AREAS = v.AREAS,
    HEIGHTS = v.HEIGHTS,
    DETERMINE = scan(AOB_DETERMINE_DOOR, "the game's door search"),
    SET_POSITION = scan(AOB_SET_POSITION, "where a unit is put down"),
    DESTINATION_RESUME = destination + SET_DESTINATION_SIZE,
  }
  w.SEARCH = assemble(templates.search, w)
  w.UNSTUCK = assemble(templates.unstuck, w)
  local entry = assemble(templates.destination, w)
  jumpTo(destination, entry, SET_DESTINATION_SIZE)
end

local function patchRepairExec(v)
  expectBytes(v.EXEC, { 0x8B, 0x44, 0x24, 0x08, 0x57, 0x8B, 0xF8 }, "the repair command")
  local code = assemble(templates.exec, {
    BUILDINGS = v.BUILDINGS,
    BUILDINGS_STATE = v.BUILDINGS_STATE,
    TYPE_COUNT = TYPE_COUNT,
    COSTS = v.COSTS,
    WOOD_RES = v.WOOD_RES,
    STONE_RES = v.STONE_RES,
    GOLD_RES = v.GOLD_RES,
    RESOURCE_LOSS = v.RESOURCE_LOSS,
    EXEC_RESUME = v.EXEC + REPAIR_EXEC_SIZE,
  })
  jumpTo(v.EXEC, code, REPAIR_EXEC_SIZE)
end

local function patchFireBlocks(v)
  local code = assemble(templates.fireBlocks, {
    SELECTED = v.SELECTED,
    BUILDINGS = v.BUILDINGS,
    ENEMY_CLOSE = v.ENEMY_CLOSE,
  })
  redirectCall(v.repairAction, REPAIR_ACTION_ENEMY_CALL, code, "the repair button's enemy test")
  redirectCall(v.repairRender, REPAIR_RENDER_ENEMY_CALL, code, "the repair button's enemy test")
end

-- writeCodeInteger: the static item table lies in the exe image.
local function setField(item, offset, value)
  if core.readInteger(item + offset) ~= value then
    core.writeCodeInteger(item + offset, value)
  end
end

---Finds the building panel's item table through the tower Repair button, and in its shared
---part (drawn for every building) the first every-frame item, the work status line and the
---bottom text line.
local function findBuildingMenu(repairAction)
  local repairItem = scan(patternOf(3, 340, 466, REPAIR_W, REPAIR_H, repairAction),
    "the building panel's Repair button")
  local start, limit = repairItem, 400
  while core.readInteger(start - ITEM_SIZE + ITEM_TYPE) ~= TYPE_LAST and limit > 0 do
    start = start - ITEM_SIZE
    limit = limit - 1
  end
  if limit == 0 or core.readInteger(start + ITEM_TYPE) ~= TYPE_EVERY_FRAME then
    error(MODULE_NAME .. ": the building panel is not the one this module knows")
  end
  local found, item = {}, start
  while core.readInteger(item + ITEM_TYPE) ~= TYPE_BLOCK do
    if core.readInteger(item + ITEM_TYPE) == 3 then
      local x, y = core.readInteger(item + ITEM_X), core.readInteger(item + ITEM_Y)
      if x == STATUS_LINE[1] and y == STATUS_LINE[2] then
        found.status = item
      elseif x == TEXT_LINE[1] and y == TEXT_LINE[2] then
        found.text = item
      end
    end
    item = item + ITEM_SIZE
  end
  if found.status == nil or found.text == nil then
    error(MODULE_NAME .. ": the building panel's status lines are not where this module expects them")
  end
  return start, found.status, found.text, repairItem
end

---Wraps the panel's items in an item list: the first every-frame item (clicks), the work status
---line (drawing) and every bottom text line (the shared one and the barracks' and mercenary
---post's own).
local function wrapItems(items, originals, wrappers)
  local item, limit, frameDone = items, 4000, false
  while core.readInteger(item + ITEM_TYPE) ~= TYPE_LAST and limit > 0 do
    local kind = core.readInteger(item + ITEM_TYPE)
    if not frameDone and kind == TYPE_EVERY_FRAME
        and core.readInteger(item + ITEM_ACTION) == originals.frame then
      setField(item, ITEM_ACTION, wrappers.frame)
      frameDone = true
    elseif kind ~= TYPE_BLOCK then
      local render = core.readInteger(item + ITEM_RENDER)
      if render == originals.render then
        setField(item, ITEM_RENDER, wrappers.render)
      elseif render == originals.text and wrappers.text ~= nil then
        setField(item, ITEM_RENDER, wrappers.text)
      end
    end
    item = item + ITEM_SIZE
    limit = limit - 1
  end
end

---Where the button goes on each panel (by tab): the default place, moved where a panel has
---its own controls there.
local function buttonPlaces(x, y)
  local places = {}
  for tab, place in pairs(PANEL_PLACES) do
    if place.absolute then
      places[tab] = { place.absolute[1], place.absolute[2] }
    else
      places[tab] = { x + place.move[1], y + place.move[2] }
    end
  end
  return places
end

local function installRepairButton(v, x, y, gold)
  local start, status, text, repairItem = findBuildingMenu(v.repairAction)
  local data = core.allocate(64 + TAB_COUNT * 8, true)
  local w = {
    VISIBLE = data,
    HOVERED = data + 1,
    GOLD_ON = data + 2,
    SCREEN_LAYER = data + 3,
    LATE_TABS = byteTable(TAB_COUNT, LATE_TABS),
    STATUS_X = STATUS_LINE[1],
    STATUS_Y = STATUS_LINE[2],
    LATE_X = LATE_LINE[1],
    LATE_Y = LATE_LINE[2],
    RECT = data + 4,
    ITEM_PLACE = data + 12,
    ORIGINAL_RENDER = data + 28,
    ORIGINAL_FRAME = data + 32,
    ORIGINAL_TEXT = data + 36,
    POSITIONS = data + 64,
    TAB_COUNT = TAB_COUNT,
    REPAIR_W = REPAIR_W,
    REPAIR_H = REPAIR_H,
    MENU_TAB = v.MENU_TAB,
    SCREEN_ID = v.SCREEN_ID,
    SELECTED = v.SELECTED,
    BUILDINGS = v.BUILDINGS,
    LOCAL_PLAYER = v.LOCAL_PLAYER,
    BUTTON_X = v.BUTTON_X,
    BUTTON_Y = v.BUTTON_Y,
    BUTTON_W = v.BUTTON_W,
    BUTTON_H = v.BUTTON_H,
    HOVER = v.HOVER,
    DISABLED = v.DISABLED,
    MOUSE = v.MOUSE,
    IS_INSIDE = v.IS_INSIDE,
    LEFT_CLICK = MOUSE_LEFT_CLICK,
    REPAIR_RENDER = v.repairRender,
    REPAIR_ACTION = v.repairAction,
    TYPE_COUNT = TYPE_COUNT,
    COSTS = v.COSTS,
    GOLD_RES = v.GOLD_RES,
    WOOD_COST = v.WOOD_COST,
    STONE_COST = v.STONE_COST,
  }
  core.writeByte(w.GOLD_ON, gold and 1 or 0)
  core.writeInteger(w.ITEM_PLACE, STATUS_LINE[1])
  core.writeInteger(w.ITEM_PLACE + 4, STATUS_LINE[2])
  for tab = 0, TAB_COUNT - 1 do
    core.writeInteger(w.POSITIONS + tab * 8, x)
    core.writeInteger(w.POSITIONS + tab * 8 + 4, y)
  end
  for tab, place in pairs(buttonPlaces(x, y)) do
    core.writeInteger(w.POSITIONS + tab * 8, place[1])
    core.writeInteger(w.POSITIONS + tab * 8 + 4, place[2])
  end
  local originals = {
    render = core.readInteger(status + ITEM_RENDER),
    frame = core.readInteger(start + ITEM_ACTION),
    text = core.readInteger(text + ITEM_RENDER),
  }
  core.writeInteger(w.ORIGINAL_RENDER, originals.render)
  core.writeInteger(w.ORIGINAL_FRAME, originals.frame)
  core.writeInteger(w.ORIGINAL_TEXT, originals.text)
  w.DRAW_BUTTON = assemble(templates.drawButton, w)
  local wrappers = {
    render = assemble(templates.render, w),
    frame = assemble(templates.click, w),
  }

  -- The repair cost text, the way the tower button shows it.
  local ok, message = pcall(function()
    local hover = scan(AOB_HOVER_HELP, "the panel's hover help")
    local costText = scan(AOB_COST_TEXT, "the repair cost text")
    expectBytes(originals.text, { 0x8B, 0x44, 0x24, 0x04, 0x50, 0xB9 }, "the bottom text line")
    local helpTable = readOperand(hover, HOVER_HELP.table, "the help texts")
    local entry = helpTable + (core.readInteger(repairItem + ITEM_HELP) & 0xFFFF) * 16
    if core.readInteger(entry) ~= HELP_REPAIR_COST then
      error("the Repair button's help text is not the repair cost")
    end
    w.HELP_ENTRY = entry
    w.BUBBLE_HELP = readOperand(hover, HOVER_HELP.bubbleHelp, "the help setting")
    w.SET_BOTTOM_TEXT = readCallTarget(hover, HOVER_HELP.setText, "the bottom text")
    w.BOTTOM_TEXT = core.readInteger(originals.text + 6)
    w.TEXT_MANAGER = readOperand(costText, COST_TEXT.textManager, "the text drawing")
    w.TEXTURE_CORE = readOperand(costText, COST_TEXT.textureCore, "the picture drawing")
    w.OPEN_TEXT = readOperand(costText, COST_TEXT.open, "the cost text")
    w.CLOSE_TEXT = readOperand(costText, COST_TEXT.close, "the cost text")
    w.TEXT_SURFACE = readOperand(costText, COST_TEXT.surface, "the text layer")
    w.DRAW_BUFFER = readOperand(costText, COST_TEXT.drawBuffer, "the picture layer")
    w.RENDER_NUMBER = readCallTarget(costText, COST_TEXT.number, "the number drawing")
    w.RENDER_GM = readCallTarget(costText, COST_TEXT.picture, "the picture drawing")
    w.SHADOW_TEXT = readCallTarget(costText, COST_TEXT.text, "the text drawing")
    w.COLOUR = COST_TEXT_COLOUR
    w.GOLD_ICON = GOLD_ICON
    w.GOLD_LINE = assemble(templates.goldLine, w)
    wrappers.text = assemble(templates.costText, w)
    local layerSite = costText + COST_TEXT_LAYER
    expectBytes(layerSite, { 0x83, 0xF8, 0x06, 0x57, 0x74 }, "the cost text layer")
    local layer = assemble(templates.layer, {
      SCREEN_LAYER = w.SCREEN_LAYER,
      SCREEN_PATH = layerSite + COST_TEXT_LAYER_SIZE + (core.readByte(layerSite + 5) & 0xFF),
      LAYER_RESUME = layerSite + COST_TEXT_LAYER_SIZE,
    })
    jumpTo(layerSite, layer, COST_TEXT_LAYER_SIZE)
  end)
  if not ok then
    log(WARNING, MODULE_NAME .. ": no repair cost text on the Repair button: " .. tostring(message))
  end

  wrapItems(start, originals, wrappers)
  local found, constructorSite = pcall(core.AOBScan, "68 " .. patternOf(start) .. " B9")
  if found and constructorSite ~= nil then
    local menu = core.readInteger(constructorSite + 6)
    local function wrapLive()
      local items = core.readInteger(menu)
      if items ~= 0 and items ~= start then
        wrapItems(items, originals, wrappers)
      end
    end
    wrapLive()
    hooks.registerHookCallback("afterInit", wrapLive)
  else
    log(WARNING, MODULE_NAME .. ": could not find the building panel itself; the Repair button "
      .. "relies on its item table")
  end
end

---AIC fields through aicloader (optional): BuildingRepairInterval in seconds and
---BuildingRepairMinimumGold, per AI character.
local function registerAICFields(intervals, minimumGold, defaultInterval, defaultGold)
  local loader = modules ~= nil and modules.aicloader or nil
  if loader == nil or loader.setAdditionalAICValue == nil then
    log(INFO, MODULE_NAME .. ": aicloader is not active; every AI repairs every "
      .. defaultInterval .. " s")
    return
  end
  local function field(name, address, default, toGame, fromGame)
    local ok, message = pcall(function()
      loader:setAdditionalAICValue(name,
        function(aiType, value)
          if aiType == nil or aiType < 1 or aiType >= AI_SLOTS then
            return nil
          end
          if value == nil then
            return fromGame(core.readInteger(address + aiType * 4))
          end
          if type(value) ~= "number" then
            log(WARNING, string.format("%s: AIC %s needs a number, got %s", MODULE_NAME, name,
              tostring(value)))
            return
          end
          core.writeInteger(address + aiType * 4, toGame(value))
        end,
        function(aiType)
          if aiType ~= nil and aiType >= 1 and aiType < AI_SLOTS then
            core.writeInteger(address + aiType * 4, toGame(default))
          end
        end)
    end)
    if not ok then
      log(WARNING, MODULE_NAME .. ": could not register AIC field " .. name .. ": " .. tostring(message))
    end
  end
  field(AIC_INTERVAL, intervals, defaultInterval,
    function(seconds)
      return math.max(1, math.tointeger(math.floor(seconds)) or defaultInterval) * TICKS_PER_SECOND
    end,
    function(ticks) return ticks // TICKS_PER_SECOND end)
  field(AIC_MINIMUM_GOLD, minimumGold, defaultGold,
    function(gold) return math.max(0, math.tointeger(math.floor(gold)) or defaultGold) end,
    function(gold) return gold end)
end

---------------------------------------------------------------------------------------
-- Enable
---------------------------------------------------------------------------------------

local function enable(self, config)
  config = config or {}
  local dynamicDoors = setting(config, "doors", "dynamic")
  local storageDoors = setting(config, "doors", "storage")
  local unstuck = setting(config, "doors", "unstuck")
  local firemen = setting(config, "firemen", "spread")
  local maces = setting(config, "blacksmith", "maces")
  local repairButton = setting(config, "repair", "button")
  local repairGold = setting(config, "repair", "gold")
  local fireBlocks = setting(config, "repair", "fire_blocks")
  local aiRepair = setting(config, "repair", "ai")
  local stables = setting(config, "stables", "breed")

  local accessible = scan(AOB_IS_ACCESSIBLE, "the game's door check")
  local repairAction = scan(AOB_REPAIR_ACTION, "the Repair button")
  local repairRender = scan(AOB_REPAIR_RENDER, "the Repair button's drawing")
  local repairExec = scan(AOB_REPAIR_EXEC, "the repair command")
  local repairCost = scan(AOB_REPAIR_COST, "the repair cost")
  local fireSearch = scan(AOB_FIRE_SEARCH, "the firemen's fire search")
  local buildingsState = readOperand(repairAction, REPAIR_ACTION.buildingsState, "the buildings")

  local v = {
    accessible = accessible,
    repairAction = repairAction,
    repairRender = repairRender,
    IS_ACCESSIBLE = accessible,
    BUILDINGS_STATE = buildingsState,
    BUILDINGS = buildingsState + 0x14,
    UNITS = readOperand(fireSearch, FIRE_UNIT_TILE, "the units") - 0xD4,
    TICKS = core.readInteger(scan(AOB_TICK_COUNTER, "the tick counter") + TICK_COUNTER_OPERAND),
    AREAS = readOperand(accessible, ACCESSIBLE_AREAS, "the area map"),
    ROWS = readOperand(accessible, ACCESSIBLE_ROWS, "the map rows"),
    HEIGHTS = readOperand(accessible, ACCESSIBLE_HEIGHTS, "the height map"),
    PATHFINDING = readOperand(accessible, ACCESSIBLE_PATHFINDING, "the path finder"),
    SELECTED = readOperand(repairAction, REPAIR_ACTION.selected, "the selected building"),
    GAME_MODE = readOperand(repairAction, REPAIR_ACTION.gameMode, "the game mode"),
    LOCAL_PLAYER = readOperand(repairAction, REPAIR_ACTION.localPlayer, "the local player"),
    WOOD_COST = readOperand(repairAction, REPAIR_ACTION.woodCost, "the repair cost"),
    STONE_COST = readOperand(repairAction, REPAIR_ACTION.stoneCost, "the repair cost"),
    ENEMY_CLOSE = readCallTarget(repairAction, REPAIR_ACTION_ENEMY_CALL, "the enemy test"),
    REPAIR_COST = repairCost,
    COSTS = readOperand(repairCost, REPAIR_COST_TABLE, "the building costs"),
    EXEC = repairExec,
    WOOD_RES = readOperand(repairExec, REPAIR_EXEC_WOOD, "the player's resources"),
    STONE_RES = readOperand(repairExec, REPAIR_EXEC_STONE, "the player's resources"),
    RESOURCE_LOSS = readCallTarget(repairExec, REPAIR_EXEC_LOSS, "the resource payment"),
  }
  v.GOLD_RES = v.WOOD_RES + RESOURCE_GOLD_FROM_WOOD
  if v.STONE_RES ~= v.WOOD_RES + 8 then
    error(MODULE_NAME .. ": the player's resources are not laid out the way this module knows")
  end
  if readCallTarget(repairRender, REPAIR_RENDER_ENEMY_CALL, "the enemy test") ~= v.ENEMY_CLOSE then
    error(MODULE_NAME .. ": the Repair button is not the one this module knows")
  end

  if maces then
    patchBlacksmith()
  end
  v.ORIGINS = core.allocate(ORIGIN_SLOTS * 12, true)
  if stables then
    patchStables(v)
  end
  patchHorseBreeding(v, config, setting(config, "stables", "panel"))
  if setting(config, "farms", "dairy_scrub") then
    patchDairyGround()
  end
  if setting(config, "hunters", "tannery") then
    patchHunters(v, config)
  end
  if firemen then
    patchFiremen(v, number(config, "firemen", "tiles", 1, 200))
  end
  if unstuck or storageDoors then
    patchUnstuck(v)
  end
  if repairGold then
    patchRepairExec(v)
  end
  if fireBlocks then
    patchFireBlocks(v)
  end
  if repairButton then
    local menu = scan(AOB_MENU_ITEM, "the menu item handler")
    local screen = readOperand(scan(AOB_KEY_GUARD, "the screen object"), KEY_GUARD_SCREEN,
      "the screen object")
    v.MENU_TAB = screen + SCREEN_MENU_TAB
    v.SCREEN_ID = screen + SCREEN_ID
    v.MOUSE = readOperand(menu, MENU_ITEM_MOUSE, "the mouse")
    v.IS_INSIDE = readCallTarget(menu, MENU_ITEM_IS_INSIDE, "the mouse test")
    v.HOVER = readOperand(repairRender, REPAIR_RENDER.hover, "the button hover flag")
    v.DISABLED = readOperand(repairRender, REPAIR_RENDER.disabled, "the button state")
    v.BUTTON_X = readOperand(repairRender, REPAIR_RENDER.buttonX, "the button position")
    v.BUTTON_Y = readOperand(repairRender, REPAIR_RENDER.buttonY, "the button position")
    v.BUTTON_W = readOperand(repairRender, REPAIR_RENDER.buttonW, "the button size")
    v.BUTTON_H = v.BUTTON_W + 4
    if v.BUTTON_Y ~= v.BUTTON_X + 4 or v.BUTTON_W ~= v.BUTTON_X + 8 then
      error(MODULE_NAME .. ": the button globals are not laid out the way this module knows")
    end
    installRepairButton(v, number(config, "repair", "x", 0, 800), number(config, "repair", "y", 0, 600),
      repairGold)
  end

  local doorTypes = {}
  if dynamicDoors then
    for _, t in ipairs(DOOR_TYPES) do doorTypes[#doorTypes + 1] = t end
  end
  if storageDoors then
    for _, t in ipairs(STORAGE_TYPES) do doorTypes[#doorTypes + 1] = t end
  end
  if #doorTypes > 0 or aiRepair then
    local site = scan(AOB_BUILDING_UPDATE, "the building update loop")
    local current = core.readInteger(site + BUILDING_UPDATE_HOOK + 2)
    expectBytes(site + BUILDING_UPDATE_HOOK, { 0x8B, 0x0D }, "the building update loop")
    local data = core.allocate(4 + 4 * 9 + AI_SLOTS * 8, true)
    local b = {
      CURRENT = current,
      BUILDINGS = v.BUILDINGS,
      BUILDINGS_STATE = v.BUILDINGS_STATE,
      TYPE_COUNT = TYPE_COUNT,
      TICKS = v.TICKS,
      DOOR_TYPES = byteTable(TYPE_COUNT, doorTypes),
      IS_ACCESSIBLE = v.IS_ACCESSIBLE,
      AI_REPAIR_ON = data,
      RESUME = site + BUILDING_UPDATE_HOOK + BUILDING_UPDATE_SIZE,
    }
    if aiRepair then
      local interval = number(config, "repair", "ai_interval", 1, 3600)
      local minimumGold = number(config, "repair", "ai_minimum_gold", 0, 1000000)
      local buy = scan(AOB_BUY_GOODS, "the market")
      local scratch = core.allocate(16, true)
      local r = {
        LAST_REPAIR = data + 4,
        INTERVALS = data + 4 + 4 * 9,
        MIN_GOLD = data + 4 + 4 * 9 + AI_SLOTS * 4,
        LAST_SCAN = scratch,
        NEED = scratch + 4,
        MISS_WOOD = scratch + 8,
        MISS_STONE = scratch + 12,
        DAMAGE = core.allocate(4, true),
        BUILDINGS = v.BUILDINGS,
        BUILDINGS_STATE = v.BUILDINGS_STATE,
        AI_TYPES = readOperand(scan(AOB_AI_TYPES, "the AI characters"), AI_TYPES_OPERAND,
          "the AI characters"),
        TICKS = v.TICKS,
        GOLD_RES = v.GOLD_RES,
        WOOD_RES = v.WOOD_RES,
        STONE_RES = v.STONE_RES,
        GAME_MODE = v.GAME_MODE,
        PATHFINDING = v.PATHFINDING,
        ENEMY_CLOSE = v.ENEMY_CLOSE,
        REPAIR_COST = v.REPAIR_COST,
        WOOD_COST = v.WOOD_COST,
        STONE_COST = v.STONE_COST,
        EXEC = v.EXEC,
        GOLD_ON = core.allocate(4, true),
        TYPE_COUNT = TYPE_COUNT,
        COSTS = v.COSTS,
        GAME_STATE = readOperand(buy, BUY_GOODS_GAME_STATE, "the market"),
        BUY_PRICE = readCallTarget(buy, BUY_GOODS_PRICE, "the market prices"),
        BUY_GOODS = buy,
        RETRY_TICKS = AI_RETRY_TICKS,
      }
      core.writeByte(r.GOLD_ON, repairGold and 1 or 0)
      core.writeInteger(r.DAMAGE, number(config, "repair", "ai_damage", 1, 99))
      for slot = 1, AI_SLOTS - 1 do
        core.writeInteger(r.INTERVALS + slot * 4, interval * TICKS_PER_SECOND)
        core.writeInteger(r.MIN_GOLD + slot * 4, minimumGold)
      end
      registerAICFields(r.INTERVALS, r.MIN_GOLD, interval, minimumGold)
      r.AI_PLAYER = assemble(templates.aiPlayer, r)
      b.AI_SCAN = assemble(templates.aiScan, r)
      b.LAST_SCAN = r.LAST_SCAN
      core.writeByte(data, 1)
    else
      b.AI_SCAN = 0
      b.LAST_SCAN = data + 4
    end
    local code = assemble(templates.buildings, b)
    jumpTo(site + BUILDING_UPDATE_HOOK, code, BUILDING_UPDATE_SIZE)
  end
end

return {
  enable = enable,
  disable = function(self, config) end,
}
