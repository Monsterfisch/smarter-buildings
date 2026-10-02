-- Assembly for smarter-buildings (FASM syntax). Every upper-case name is a constant that
-- init.lua passes in; only the names a script uses are handed to the assembler.
local templates = {}

-- Stables: wraps the call in euroRecruit that ties a new knight to a stable's horse
-- (thiscall on GameState, args player, unit, ret 8). The horse leaves the stable with the
-- knight: its stall is emptied, so the stable breeds a new one, and the knight is not tied
-- to the stable any more (the call answers 0). ORIGINS keeps, per unit slot, which stable
-- (id, unit uid, stable uid) the knight's horse came from, for the breeding time.
templates.stables = [[
push dword [esp+8]
push dword [esp+8]
call LINKAGE
test eax,eax
je s_done
push ebx
push esi
imul ebx,eax,0x32C
add ebx,BUILDINGS
mov ecx,[esp+0x10]
xor esi,esi
s_loop:
cmp word [ebx+esi*2+0x2E0],cx
jne s_next
cmp ecx,ORIGIN_SLOTS
jae s_free
lea edx,[ecx+ecx*2]
mov [ORIGINS+edx*4],eax
push eax
imul eax,ecx,0x490
mov eax,[eax+UNITS+0x98]
mov [ORIGINS+edx*4+4],eax
pop eax
push dword [ebx+0xD8]
pop dword [ORIGINS+edx*4+8]
s_free:
mov word [ebx+esi*2+0x2E0],0
mov dword [ebx+esi*4+0x2E8],0
cmp byte [ebx+0x2A7],0
jle s_animals
dec byte [ebx+0x2A7]
s_animals:
cmp byte [ebx+0x297],0
jle s_unlinked
dec byte [ebx+0x297]
s_unlinked:
pop esi
pop ebx
xor eax,eax
ret 8
s_next:
inc esi
cmp esi,4
jb s_loop
pop esi
pop ebx
s_done:
ret 8
]]

-- countKnights(stable), stdcall: the knights alive that took a horse from this stable (ORIGINS
-- per unit slot: stable, unit uid, stable uid).
templates.countKnights = [[
push ebx
push esi
push edi
push ebp
mov edi,[esp+0x14]
imul ebp,edi,0x32C
mov ebp,[ebp+BUILDINGS+0xD8]
xor ebx,ebx
mov ecx,[UNITS_STATE]
cmp ecx,ORIGIN_SLOTS
jbe k_slots
mov ecx,ORIGIN_SLOTS
k_slots:
mov edx,1
k_loop:
cmp edx,ecx
jge k_done
lea eax,[edx+edx*2]
cmp [ORIGINS+eax*4],edi
jne k_next
cmp [ORIGINS+eax*4+8],ebp
jne k_next
imul esi,edx,0x490
cmp word [esi+UNITS+0x8C],0
je k_next
mov esi,[esi+UNITS+0x98]
cmp esi,[ORIGINS+eax*4+4]
jne k_next
inc ebx
k_next:
inc edx
jmp k_loop
k_done:
mov eax,ebx
pop ebp
pop edi
pop esi
pop ebx
ret 4
]]

-- breedLimit(stable), stdcall: the ticks the stable's next horse takes. Its horses alive are
-- those in its stalls plus its knights (KNIGHTS, recounted every 64 ticks). Up to NORMAL of them
-- breed in BASE ticks, each further one takes FACTOR times as long, up to SLOWEST.
templates.breedLimit = [[
mov edx,[esp+4]
imul ecx,edx,0x32C
movzx eax,byte [ecx+BUILDINGS+0x297]
add eax,[KNIGHTS+edx*4]
mov ecx,[BASE]
sub eax,[NORMAL]
jl l_done
inc eax
l_more:
test eax,eax
jle l_done
imul ecx,[FACTOR]
cmp ecx,[SLOWEST]
jge l_slowest
dec eax
jmp l_more
l_slowest:
mov ecx,[SLOWEST]
l_done:
mov eax,ecx
ret 4
]]

-- UpdateStables, where a stable with fewer than four horses counts towards the next one
-- (add word [counter],1 / movzx / cmp ax,0x226 / jle: 20 bytes replaced). esi = building *
-- 0x32C, edi = building, ebx = 1, ebp = 0. The count is kept here instead (a dword per
-- building, COUNTERS) against breedLimit.
templates.breeding = [[
pushad
cmp edi,2000
jae h_later
mov eax,[TICKS]
add eax,edi
and eax,63
jne h_known
push edi
call COUNT_KNIGHTS
mov [KNIGHTS+edi*4],eax
h_known:
push edi
call BREED_LIMIT
inc dword [COUNTERS+edi*4]
cmp [COUNTERS+edi*4],eax
jle h_later
mov dword [COUNTERS+edi*4],0
popad
jmp BREED_NOW
h_later:
popad
jmp BREED_LATER
]]

-- The stable panel's "in use" number (movsx edx, byte [esi + stalls kept]; 7 bytes replaced,
-- eax/ecx hold the panel's place): the stalls kept plus the stable's knights alive. The panel's
-- "1 or more" test reads IN_USE too.
templates.stableInUse = [[
push eax
push ecx
push dword [SELECTED]
call COUNT_KNIGHTS
movsx edx,byte [esi+STALLS_KEPT]
add edx,eax
mov [IN_USE],edx
pop ecx
pop eax
jmp IN_USE_RESUME
]]

-- The stable panel (RenderBuildingMenu_Stables, its first 5 bytes jump here): draw it, then a
-- bar like the towers' health bar for the next horse - lime as far as the breeding has got,
-- full when the stalls are full.
templates.stablePanel = [[
call p_original
pushad
mov edi,[SELECTED]
test edi,edi
jle p_done
cmp edi,2000
jge p_done
imul esi,edi,0x32C
add esi,BUILDINGS
mov ebx,BAR_WIDTH
cmp byte [esi+0x297],4
jge p_draw
push edi
call BREED_LIMIT
mov ecx,[COUNTERS+edi*4]
cmp ecx,eax
jle p_within
mov ecx,eax
p_within:
push eax
mov eax,ecx
imul eax,eax,BAR_WIDTH
cdq
idiv dword [esp]
add esp,4
mov ebx,eax
p_draw:
mov eax,[MENU_X]
add eax,BAR_X
mov [BAR],eax
mov eax,[MENU_Y]
add eax,BAR_Y
mov [BAR+4],eax
movzx eax,word [BLACK]
push eax
mov eax,[BAR+4]
add eax,11
push eax
mov eax,[BAR]
add eax,BAR_WIDTH+1
push eax
push dword [BAR+4]
push dword [BAR]
mov ecx,PENCIL
call BORDER_BOX
movzx eax,word [RED]
push eax
mov eax,[BAR+4]
add eax,10
push eax
mov eax,[BAR]
add eax,BAR_WIDTH
push eax
mov eax,[BAR+4]
inc eax
push eax
mov eax,[BAR]
inc eax
push eax
mov ecx,PENCIL
call COLOUR_BOX
cmp ebx,1
jl p_done
movzx eax,word [LIME]
push eax
mov eax,[BAR+4]
add eax,10
push eax
mov eax,[BAR]
add eax,ebx
push eax
mov eax,[BAR+4]
inc eax
push eax
mov eax,[BAR]
inc eax
push eax
mov ecx,PENCIL
call COLOUR_BOX
p_done:
popad
ret
p_original:
mov eax,[MENU_Y]
jmp PANEL_RESUME
]]

-- checkBuildingCanBePlacedHere, after every footprint tile has been found grass of some kind:
-- cmp dword [esp+0x20],50 (tiles of oasis grass or thick scrub) is replaced. For a dairy farm
-- (command 0x49) the count that also has thin scrub ([esp+0x48]) is used instead.
templates.dairyGround = [[
cmp ax,DAIRY_COMMAND
jne g_other
cmp dword [esp+0x48],FERTILE_TILES
jmp GROUND_RESUME
g_other:
cmp dword [esp+0x20],FERTILE_TILES
jmp GROUND_RESUME
]]

-- UpdateTanner, when the tanner has finished skinning a cow at his tannery (imul edi,edi,0x490
-- replaced; edi = the tanner): the tannery keeps the carcass, up to STORED_MAX. CARCASSES has
-- a count and the tannery's uid per building.
templates.tannerCarcass = [[
push eax
push ecx
mov eax,edi
imul eax,eax,0x490
movsx eax,word [eax+UNITS+0x338]
cmp eax,0
jle c_done
cmp eax,2000
jge c_done
imul ecx,eax,0x32C
mov ecx,[ecx+BUILDINGS+0xD8]
cmp ecx,[CARCASSES+eax*8+4]
je c_same
mov [CARCASSES+eax*8+4],ecx
mov dword [CARCASSES+eax*8],0
c_same:
cmp dword [CARCASSES+eax*8],STORED_MAX
jge c_done
inc dword [CARCASSES+eax*8]
c_done:
pop ecx
pop eax
imul edi,edi,0x490
jmp TANNER_RESUME
]]

-- UpdateHunter, state 0 at his post with no meat stored, where he looks for deer (push edi /
-- mov ecx,UnitsState replaced; edi = the hunter, esi = hunter * 0x490, ebp = post * 0x32C).
-- A carcass he brought along beyond the first is butchered next, the way the game butchers the
-- one he carried in. With no deer left on the map he goes to a tannery of his lord that keeps
-- carcasses and takes up to CARRY of them: the game's own "walk to the shot deer, then carry it
-- home" state (0xB) with the tannery's door as the deer and himself as the deer unit.
templates.hunterTannery = [[
pushad
cmp edi,UNIT_SLOTS
jae h_game
mov eax,[esi+UNITS+0x98]
cmp eax,[EXTRA+edi*8+4]
jne h_tannery
cmp dword [EXTRA+edi*8],0
jle h_tannery
dec dword [EXTRA+edi*8]
mov word [esi+UNITS+0x2C0],0x6D
mov byte [esi+UNITS+0x32E],0
mov byte [esi+UNITS+0x32F],2
mov word [esi+UNITS+0x2C2],3
mov word [esi+UNITS+0x2C8],0
popad
jmp HUNTER_TAIL
h_tannery:
mov ecx,[UNITS_STATE]
mov edx,UNITS+0x490
mov eax,1
h_deer:
cmp eax,ecx
jge h_no_deer
cmp word [edx+0x8E],DEER
jne h_next_deer
cmp word [edx+0x8C],0
jne h_game
h_next_deer:
add edx,0x490
inc eax
jmp h_deer
h_no_deer:
movsx edx,word [esi+UNITS+0x96]
mov ebx,1
h_find:
cmp ebx,[BUILDINGS_STATE+8]
jge h_game
cmp ebx,2000
jge h_game
cmp dword [CARCASSES+ebx*8],0
jle h_next
imul ecx,ebx,0x32C
add ecx,BUILDINGS
cmp word [ecx+0xD0],0
je h_next
cmp word [ecx+0xD2],TANNERY
jne h_next
movsx eax,word [ecx+0xD6]
cmp eax,edx
jne h_next
mov eax,[ecx+0xD8]
cmp eax,[CARCASSES+ebx*8+4]
jne h_next
push edx
push ecx
push 0
movsx eax,word [ecx+0x100]
push eax
movsx eax,word [ecx+0xFE]
push eax
push edi
mov ecx,UNITS_STATE
call SET_DESTINATION
pop ecx
pop edx
test eax,eax
jne h_found
h_next:
inc ebx
jmp h_find
h_found:
mov eax,[CARCASSES+ebx*8]
cmp eax,CARRY
jle h_take
mov eax,CARRY
h_take:
sub [CARCASSES+ebx*8],eax
dec eax
mov [EXTRA+edi*8],eax
mov eax,[esi+UNITS+0x98]
mov [EXTRA+edi*8+4],eax
mov ax,[ebp+BUILDINGS+0xFE]
mov [esi+UNITS+0x33A],ax
mov ax,[ebp+BUILDINGS+0x100]
mov [esi+UNITS+0x33C],ax
mov [esi+UNITS+0x344],di
mov eax,[esi+UNITS+0x98]
mov [esi+UNITS+0x3A0],eax
mov word [esi+UNITS+0x2C0],0xB
popad
jmp HUNTER_TAIL
h_game:
popad
push edi
mov ecx,UNITS_STATE
jmp HUNTER_RESUME
]]

-- Firemen: inside findClosestReachableAlliedBuilding, right after the distance to a burning
-- building is worked out. Every other fireman already on his way to that fire (state 3) or
-- putting it out (state 4) makes it look PENALTY tiles further away. ebx = building index,
-- esi = building + 0xD0, edi = unit index * 0x490.
templates.firemen = [[
pushad
mov edx,edi
add edx,UNITS
mov ebp,[esi+8]
xor eax,eax
mov ecx,[UNITS_STATE]
mov edi,UNITS+0x490
mov esi,1
f_loop:
cmp esi,ecx
jge f_done
cmp edi,edx
je f_next
cmp word [edi+0x8E],FIREMAN
jne f_next
cmp word [edi+0x8C],0
je f_next
cmp word [edi+0x2C0],3
je f_target
cmp word [edi+0x2C0],4
jne f_next
f_target:
cmp word [edi+0x39E],bx
jne f_next
cmp [edi+0x3A0],ebp
jne f_next
inc eax
f_next:
add edi,0x490
inc esi
jmp f_loop
f_done:
imul eax,eax,PENALTY
add [DISTANCE],eax
popad
mov eax,[esp+0x10]
cmp [DISTANCE],eax
jmp RESUME
]]

-- updateBuildings, right after a building's own update: mov ecx,[current building] is
-- replaced. Once a tick (the first building updated): the AI lords' repairs. Once every 64
-- ticks per building (spread by building id): re-check the door of the building types in
-- DOOR_TYPES with the game's own buildingIsAccessible, which moves a blocked or cut-off door.
templates.buildings = [[
pushad
cmp byte [AI_REPAIR_ON],0
je b_doors
mov eax,[TICKS]
cmp eax,[LAST_SCAN]
je b_doors
mov [LAST_SCAN],eax
call AI_SCAN
b_doors:
mov esi,[CURRENT]
imul edi,esi,0x32C
add edi,BUILDINGS
cmp word [edi+0xD0],0
je b_done
movsx ebx,word [edi+0xD2]
cmp ebx,TYPE_COUNT
jae b_done
mov eax,[TICKS]
add eax,esi
and eax,63
jne b_done
cmp byte [DOOR_TYPES+ebx],0
je b_done
push 0
push esi
mov ecx,BUILDINGS_STATE
call IS_ACCESSIBLE
b_done:
popad
mov ecx,[CURRENT]
jmp RESUME
]]

-- aiScan(), cdecl: every AI lord whose repair interval has passed and who has more gold than
-- his minimum gets aiPlayerRepair.
templates.aiScan = [[
pushad
mov ebx,1
s_player:
cmp ebx,8
jg s_end
imul ebp,ebx,0x39F4
mov eax,[ebp+AI_TYPES]
test eax,eax
je s_next
cmp eax,16
ja s_next
mov ecx,[TICKS]
sub ecx,[LAST_REPAIR+ebx*4]
cmp ecx,[INTERVALS+eax*4]
jb s_next
mov ecx,[ebp+GOLD_RES]
cmp ecx,[MIN_GOLD+eax*4]
jle s_next
push ebx
call AI_PLAYER
s_next:
inc ebx
jmp s_player
s_end:
popad
ret
]]

-- aiPlayerRepair(player), stdcall: goes through the building array for the lord's most damaged
-- building (at least DAMAGE percent below its full health) that does not burn and has no enemy
-- near, works out the repair cost (wood, stone, gold share), buys the wood and stone he lacks
-- at the market price (the game's own buyGoods) and repairs it through EXEC. When nothing can be
-- repaired or paid for, he looks again RETRY_TICKS later.
templates.aiPlayer = [[
push ebx
push esi
push edi
push ebp
mov ebx,[esp+0x14]
xor edi,edi
xor ebp,ebp
mov esi,1
p_loop:
cmp esi,[BUILDINGS_STATE+8]
jge p_chosen
cmp esi,2000
jge p_chosen
imul ecx,esi,0x32C
add ecx,BUILDINGS
cmp word [ecx+0xD0],0
je p_next
movsx eax,word [ecx+0xD6]
cmp eax,ebx
jne p_next
cmp word [ecx+0x2BE],0
jne p_next
movsx edx,word [ecx+0x10E]
test edx,edx
jle p_next
movsx eax,word [ecx+0x10C]
neg eax
add eax,edx
jle p_next
imul eax,eax,100
push ecx
mov ecx,edx
cdq
idiv ecx
pop ecx
cmp eax,[DAMAGE]
jl p_next
cmp eax,ebp
jle p_next
push eax
mov eax,30
cmp dword [GAME_MODE],0
je p_range
mov eax,15
p_range:
push eax
movsx eax,word [ecx+0xF0]
push eax
movsx eax,word [ecx+0xEE]
push eax
push ebx
mov ecx,PATHFINDING
call ENEMY_CLOSE
mov edx,eax
pop eax
test edx,edx
jne p_next
mov ebp,eax
mov edi,esi
p_next:
inc esi
jmp p_loop
p_chosen:
test edi,edi
je p_none
push edi
mov ecx,BUILDINGS_STATE
call REPAIR_COST
test eax,eax
je p_none
imul esi,ebx,0x39F4
xor eax,eax
cmp byte [GOLD_ON],0
je p_gold
imul ecx,edi,0x32C
add ecx,BUILDINGS
movsx edx,word [ecx+0xD2]
cmp edx,TYPE_COUNT
jae p_gold
imul edx,edx,20
mov eax,[edx+COSTS+16]
test eax,eax
jle p_nogold
movsx ebp,word [ecx+0x10E]
movsx edx,word [ecx+0x10C]
neg edx
add edx,ebp
imul eax,edx
cdq
idiv ebp
cmp eax,1
jge p_gold
mov eax,1
jmp p_gold
p_nogold:
xor eax,eax
p_gold:
mov [NEED],eax
mov eax,[WOOD_COST]
sub eax,[esi+WOOD_RES]
jg p_wood
xor eax,eax
p_wood:
mov [MISS_WOOD],eax
mov eax,[STONE_COST]
sub eax,[esi+STONE_RES]
jg p_stone
xor eax,eax
p_stone:
mov [MISS_STONE],eax
cmp dword [MISS_WOOD],0
je p_wood_priced
push dword [MISS_WOOD]
push 2
push ebx
mov ecx,GAME_STATE
call BUY_PRICE
add [NEED],eax
p_wood_priced:
cmp dword [MISS_STONE],0
je p_stone_priced
push dword [MISS_STONE]
push 4
push ebx
mov ecx,GAME_STATE
call BUY_PRICE
add [NEED],eax
p_stone_priced:
mov eax,[NEED]
cmp eax,[esi+GOLD_RES]
jg p_none
cmp dword [MISS_WOOD],0
je p_wood_bought
push dword [MISS_WOOD]
push 2
push ebx
call BUY_GOODS
test eax,eax
je p_none
p_wood_bought:
cmp dword [MISS_STONE],0
je p_stone_bought
push dword [MISS_STONE]
push 4
push ebx
call BUY_GOODS
test eax,eax
je p_none
p_stone_bought:
imul ecx,edi,0x32C
add ecx,BUILDINGS
push dword [ecx+0xD8]
push dword [STONE_COST]
push dword [WOOD_COST]
push edi
push ebx
call EXEC
add esp,20
mov eax,[TICKS]
mov [LAST_REPAIR+ebx*4],eax
jmp p_out
p_none:
imul ecx,ebx,0x39F4
mov ecx,[ecx+AI_TYPES]
mov ecx,[INTERVALS+ecx*4]
mov eax,[TICKS]
sub eax,ecx
add eax,RETRY_TICKS
mov [LAST_REPAIR+ebx*4],eax
p_out:
pop ebp
pop edi
pop esi
pop ebx
ret 4
]]

-- ProcessTowerRepair(player, building, wood, stone, uid), cdecl: the repair command. Its
-- first 7 bytes jump here. Charges the gold share of the repair as well (the game only
-- charges wood and stone) and refuses a repair the player cannot pay for.
templates.exec = [[
push ebx
push esi
push edi
mov esi,[esp+0x14]
cmp esi,0
jle x_pass
imul edi,esi,0x32C
add edi,BUILDINGS
mov eax,[edi+0xD8]
cmp eax,[esp+0x20]
jne x_pass
movsx ecx,word [edi+0xD2]
cmp ecx,TYPE_COUNT
jae x_pass
imul ecx,ecx,20
mov ecx,[ecx+COSTS+16]
test ecx,ecx
jle x_pass
movsx ebx,word [edi+0x10E]
test ebx,ebx
jle x_pass
movsx eax,word [edi+0x10C]
neg eax
add eax,ebx
jle x_pass
imul eax,ecx
cdq
idiv ebx
cmp eax,1
jge x_have
mov eax,1
x_have:
mov ebx,eax
mov ecx,[esp+0x10]
imul ecx,ecx,0x39F4
mov edx,[esp+0x18]
cmp edx,[ecx+WOOD_RES]
jg x_pass
mov edx,[esp+0x1C]
cmp edx,[ecx+STONE_RES]
jg x_pass
cmp ebx,[ecx+GOLD_RES]
jg x_refuse
push 0
push ebx
push 15
push dword [esp+0x1C]
mov ecx,BUILDINGS_STATE
call RESOURCE_LOSS
x_pass:
pop edi
pop esi
pop ebx
mov eax,[esp+8]
push edi
mov edi,eax
jmp EXEC_RESUME
x_refuse:
pop edi
pop esi
pop ebx
ret
]]

-- isEnemyTooCloseUnk as the repair button asks it (thiscall, ret 0x10): a burning building
-- counts as "enemy near", so the button is greyed out and does nothing.
templates.fireBlocks = [[
mov eax,[SELECTED]
imul eax,eax,0x32C
cmp word [eax+BUILDINGS+0x2BE],0
je e_orig
mov eax,1
ret 0x10
e_orig:
jmp ENEMY_CLOSE
]]

-- drawButton(itemX, itemY), stdcall: draws the game's own Repair button for the selected
-- building when it is the local player's and damaged, at the place POSITIONS gives for the
-- open panel (by tab; entry 0 is the default). itemX/Y is where the calling item sits, to find
-- the panel's origin from BUTTON_X/Y. Towers and gates (tabs 36 and 46) have the button
-- already. Sets VISIBLE, HOVERED and RECT for the click and the cost text.
templates.drawButton = [[
push esi
push edi
mov esi,[BUTTON_X]
mov edi,[BUTTON_Y]
cmp dword [MENU_TAB],36
je w_out
cmp dword [MENU_TAB],46
je w_out
mov eax,[SELECTED]
test eax,eax
jle w_out
cmp eax,2000
jge w_out
imul ecx,eax,0x32C
add ecx,BUILDINGS
cmp word [ecx+0xD0],0
je w_out
movsx edx,word [ecx+0xD6]
cmp edx,[LOCAL_PLAYER]
jne w_out
movsx edx,word [ecx+0x10E]
test edx,edx
jle w_out
cmp dx,word [ecx+0x10C]
jle w_out
mov eax,[MENU_TAB]
cmp eax,TAB_COUNT
jb w_tab
xor eax,eax
w_tab:
sub esi,[esp+12]
add esi,[POSITIONS+eax*8]
sub edi,[esp+16]
add edi,[POSITIONS+eax*8+4]
mov [RECT],esi
mov [RECT+4],edi
push dword [BUTTON_X]
push dword [BUTTON_Y]
push dword [BUTTON_W]
push dword [BUTTON_H]
push dword [HOVER]
push dword [DISABLED]
mov [BUTTON_X],esi
mov [BUTTON_Y],edi
mov dword [BUTTON_W],REPAIR_W
mov dword [BUTTON_H],REPAIR_H
push REPAIR_H
push REPAIR_W
push edi
push esi
mov ecx,MOUSE
call IS_INSIDE
mov [HOVER],eax
mov [HOVERED],al
push 0
call REPAIR_RENDER
add esp,4
mov byte [VISIBLE],1
pop dword [DISABLED]
pop dword [HOVER]
pop dword [BUTTON_H]
pop dword [BUTTON_W]
pop dword [BUTTON_Y]
pop dword [BUTTON_X]
w_out:
pop edi
pop esi
ret 8
]]

-- The building panel's work status line (drawn for every building, before the panel's own
-- items): draw it, then the Repair button - except on panels whose own items would cover it
-- (LATE_TABS: barracks, mercenary post), which draw it from their own bottom text line.
templates.render = [[
push dword [esp+4]
call dword [ORIGINAL_RENDER]
add esp,4
mov byte [HOVERED],0
mov eax,[MENU_TAB]
cmp eax,TAB_COUNT
jae w_draw
cmp byte [LATE_TABS+eax],0
jne w_done
w_draw:
push STATUS_Y
push STATUS_X
call DRAW_BUTTON
w_done:
ret
]]

-- The building panel's first every-frame item: a left click on the Repair button drawn in
-- the last frame runs the game's own repair button action and is used up.
templates.click = [[
cmp byte [VISIBLE],0
je c_pass
mov byte [VISIBLE],0
cmp dword [MOUSE+LEFT_CLICK],0
je c_pass
push REPAIR_H
push REPAIR_W
push dword [RECT+4]
push dword [RECT]
mov ecx,MOUSE
call IS_INSIDE
test eax,eax
je c_pass
mov dword [MOUSE+LEFT_CLICK],0
push 0
call REPAIR_ACTION
add esp,4
c_pass:
jmp dword [ORIGINAL_FRAME]
]]

-- The panel's bottom text lines (MenuItemActionHandler_General_DisplayConditionalText, cdecl,
-- one parameter: 0 for the shared line above the panel, 1 for the barracks' and mercenary
-- post's own line inside it, drawn after their portraits). The own line draws the Repair button
-- there. While the mouse is on the button, put the game's own repair cost text in the line, as
-- the tower button does (only with the game's help texts switched on). The own line is inside
-- the panel, so the text goes on the screen layer there (SCREEN_LAYER) instead of the map
-- layer the game uses for a cost line. After the line is drawn, a repair cost line gets the
-- gold share as well when gold is charged.
templates.costText = [[
cmp dword [esp+4],0
je t_help
mov eax,[MENU_TAB]
cmp eax,TAB_COUNT
jae t_help
cmp byte [LATE_TABS+eax],0
je t_help
push LATE_Y
push LATE_X
call DRAW_BUTTON
t_help:
cmp byte [HOVERED],0
je t_show
cmp dword [BUBBLE_HELP],0
je t_show
push -1
push 0x32
push dword [HELP_ENTRY+12]
push dword [HELP_ENTRY+8]
push dword [HELP_ENTRY+4]
push dword [HELP_ENTRY]
mov ecx,BOTTOM_TEXT
call SET_BOTTOM_TEXT
t_show:
cmp dword [esp+4],0
setne byte [SCREEN_LAYER]
push dword [esp+4]
call dword [ORIGINAL_TEXT]
add esp,4
cmp byte [GOLD_ON],0
je t_out
cmp dword [BOTTOM_TEXT],8
jne t_out
cmp dword [esp+4],0
jne t_gold
cmp dword [SCREEN_ID],0x10
jne t_gold
cmp dword [MENU_TAB],1
je t_out
cmp dword [MENU_TAB],0x2C
je t_out
t_gold:
call GOLD_LINE
t_out:
mov byte [SCREEN_LAYER],0
ret
]]

-- renderCurrentlyDisplayedTextConstructionCost, where it picks the layer: kinds 6, 7, 0xC and
-- 0xD go on the screen layer, everything else on the map layer with the camera offset. A
-- repair cost line (kind 8) drawn from a line inside the panel goes on the screen layer too.
templates.layer = [[
push edi
cmp eax,6
je SCREEN_PATH
cmp eax,8
jne l_back
cmp byte [SCREEN_LAYER],0
jne SCREEN_PATH
l_back:
jmp LAYER_RESUME
]]

-- goldLine(), cdecl: after the game has drawn a repair cost line ("cost [wood] (have)"
-- "cost [stone] (have)"), add "cost [gold] (have)" for the selected building the same way, on
-- the same layer: on the map layer the game has already moved BUTTON_X/Y to where the line is
-- drawn and left the picture layer as it draws the wood and stone pictures; on the screen layer
-- the pictures need DRAW_BUFFER 0, as the game's own screen cost lines set it.
templates.goldLine = [[
push ebx
push esi
push edi
push ebp
mov eax,[SELECTED]
test eax,eax
jle g_out
cmp eax,2000
jge g_out
imul edi,eax,0x32C
add edi,BUILDINGS
movsx ecx,word [edi+0xD2]
cmp ecx,TYPE_COUNT
jae g_out
imul ecx,ecx,20
mov ecx,[ecx+COSTS+16]
test ecx,ecx
jle g_out
movsx ebx,word [edi+0x10E]
test ebx,ebx
jle g_out
movsx eax,word [edi+0x10C]
neg eax
add eax,ebx
jle g_out
imul eax,ecx
cdq
idiv ebx
cmp eax,1
jge g_have
mov eax,1
g_have:
mov ebp,eax
mov esi,0x1E
cmp dword [WOOD_COST],0
je g_stone
add esi,0x40
g_stone:
cmp dword [STONE_COST],0
je g_draw
add esi,0x40
g_draw:
cmp byte [SCREEN_LAYER],0
jne g_screen
mov dword [TEXT_SURFACE],1
g_screen:
push 0
push 1
push 0x12
push 0
push COLOUR
push 0
push dword [BUTTON_Y]
mov eax,[BUTTON_X]
add eax,esi
push eax
push ebp
mov ecx,TEXT_MANAGER
call RENDER_NUMBER
cmp byte [SCREEN_LAYER],0
je g_coin
mov dword [DRAW_BUFFER],0
g_coin:
mov eax,[BUTTON_Y]
sub eax,4
push eax
mov eax,[TEXT_MANAGER]
add eax,[BUTTON_X]
lea eax,[eax+esi+2]
push eax
push GOLD_ICON
push 0x2E
mov ecx,TEXTURE_CORE
call RENDER_GM
add esi,0x20
push 0
push 1
push 0x12
push 0
push COLOUR
push 0
push dword [BUTTON_Y]
mov eax,[BUTTON_X]
add eax,esi
push eax
push OPEN_TEXT
mov ecx,TEXT_MANAGER
call SHADOW_TEXT
mov eax,[LOCAL_PLAYER]
imul eax,eax,0x39F4
mov eax,[eax+GOLD_RES]
push 0
push 1
push 0x12
push 0
push COLOUR
push 0
push dword [BUTTON_Y]
mov ecx,[BUTTON_X]
add ecx,esi
push ecx
push eax
mov ecx,TEXT_MANAGER
call RENDER_NUMBER
push 0
push 1
push 0x12
push 0
push COLOUR
push 0
push dword [BUTTON_Y]
mov eax,[BUTTON_X]
add eax,esi
push eax
push CLOSE_TEXT
mov ecx,TEXT_MANAGER
call SHADOW_TEXT
mov dword [TEXT_SURFACE],0
mov dword [DRAW_BUFFER],1
g_out:
pop ebp
pop edi
pop esi
pop ebx
ret
]]

-- unstuck(unit, x, y), stdcall: a worker standing on his workplace's door could not find a
-- way to (x, y). Walk the door clockwise round the building (the game's own door search,
-- started one step further each time), skipping doors in the same area as the last door
-- that failed; put the worker on each new door and ask again. Keep the first door that works,
-- or put door and worker back where they were.
templates.unstuck = [[
push ebx
push esi
push edi
push ebp
sub esp,36
mov eax,[esp+0x38]
cmp eax,0
jle u_fail
imul esi,eax,0x490
add esi,UNITS
movsx eax,word [esi+0x8E]
cmp eax,UNIT_TYPE_COUNT
jae u_fail
cmp byte [WORKER_TYPES+eax],0
je u_fail
movsx ebx,word [esi+0x338]
test ebx,ebx
jle u_fail
cmp ebx,2000
jge u_fail
imul edi,ebx,0x32C
add edi,BUILDINGS
cmp word [edi+0xD0],0
je u_fail
mov eax,[edi+0xD8]
cmp eax,[esi+0x368]
jne u_fail
mov ax,[esi+0xC4]
cmp ax,[edi+0xFE]
jne u_fail
mov ax,[esi+0xC6]
cmp ax,[edi+0x100]
jne u_fail
mov eax,[TICKS]
mov ecx,eax
sub ecx,[TRIED+ebx*4]
cmp ecx,RETRY_TICKS
jb u_fail
mov [TRIED+ebx*4],eax
movsx eax,word [edi+0xFE]
mov [esp],eax
mov [esp+0xC],eax
movsx eax,word [edi+0x100]
mov [esp+4],eax
mov [esp+0x10],eax
movzx eax,word [edi+0xFC]
mov [esp+8],eax
mov eax,[esp+4]
lea eax,[eax+eax*2]
mov eax,[ROWS+eax*4]
add eax,[esp]
movsx eax,word [AREAS+eax*2]
mov [esp+0x14],eax
mov [esp+0x20],eax
mov dword [esp+0x18],0
mov dword [esp+0x1C],0
mov byte [BUSY],1
u_next:
inc dword [esp+0x18]
cmp dword [esp+0x18],MAX_TRIES
jg u_back
inc word [edi+0xFC]
push 0
push 0
push ebx
mov ecx,BUILDINGS_STATE
call DETERMINE
test eax,eax
je u_back
movsx ecx,word [edi+0xFE]
movsx edx,word [edi+0x100]
cmp ecx,[esp]
jne u_new
cmp edx,[esp+4]
je u_back
u_new:
cmp ecx,[esp+0xC]
jne u_fresh
cmp edx,[esp+0x10]
je u_next
u_fresh:
mov [esp+0xC],ecx
mov [esp+0x10],edx
lea eax,[edx+edx*2]
mov eax,[ROWS+eax*4]
add eax,ecx
movsx ebp,word [AREAS+eax*2]
cmp ebp,[esp+0x20]
je u_next
mov [esp+0x20],ebp
movzx eax,byte [HEIGHTS+eax]
push eax
push edx
push ecx
push dword [esp+0x38+12]
mov ecx,[UNITS_THIS]
call SET_POSITION
mov dword [esp+0x1C],1
push 0
push dword [esp+0x40+4]
push dword [esp+0x3C+8]
push dword [esp+0x38+12]
mov ecx,[UNITS_THIS]
call SEARCH
test eax,eax
je u_next
mov byte [BUSY],0
jmp u_out
u_back:
mov ax,[esp]
mov [edi+0xFE],ax
mov ax,[esp+4]
mov [edi+0x100],ax
mov eax,[esp+8]
mov [edi+0xFC],ax
cmp dword [esp+0x1C],0
je u_idle
mov eax,[esp+4]
lea ecx,[eax+eax*2]
mov ecx,[ROWS+ecx*4]
add ecx,[esp]
movzx ecx,byte [HEIGHTS+ecx]
push ecx
push eax
push dword [esp+8]
push dword [esp+0x38+12]
mov ecx,[UNITS_THIS]
call SET_POSITION
u_idle:
mov byte [BUSY],0
u_fail:
xor eax,eax
u_out:
add esp,36
pop ebp
pop edi
pop esi
pop ebx
ret 12
]]

-- setDestinationForUnit(unit, x, y, mode), thiscall on UnitsState, ret 0x10: its first 7
-- bytes jump here. A normal search (mode 0) that fails is handed to UNSTUCK.
templates.destination = [[
cmp byte [BUSY],0
jne SEARCH
mov [UNITS_THIS],ecx
push dword [esp+0x10]
push dword [esp+0x10]
push dword [esp+0x10]
push dword [esp+0x10]
call SEARCH
test eax,eax
jne d_ret
cmp dword [esp+0x10],0
jne d_ret
push dword [esp+0xC]
push dword [esp+0xC]
push dword [esp+0xC]
call UNSTUCK
d_ret:
ret 0x10
]]

-- The unpatched setDestinationForUnit: its first 7 bytes, then on into the rest of it.
templates.search = [[
sub esp,8
mov eax,[esp+0xC]
jmp DESTINATION_RESUME
]]

return templates
