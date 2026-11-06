-- BuffCheck – zeigt fehlende Selbst-Buffs für WoW Forever
-- Kern: Prüfung anstoßen, Events, Slash-Befehle. Die Teile liegen in Modules.

local ADDON, ns = ...
local L = ns.L

local ALCH_SLOTS, CLASS, CLASS_ROLE, GROUPS = ns.ALCH_SLOTS, ns.CLASS, ns.CLASS_ROLE, ns.GROUPS
local ICON_SIZE, ROLE_NAMES, ROLE_SLOTS, alchemySkill = ns.ICON_SIZE, ns.ROLE_NAMES, ns.ROLE_SLOTS, ns.alchemySkill
local anchor, buttons, campBlockedSpells, campBuff = ns.anchor, ns.buttons, ns.campBlockedSpells, ns.campBuff
local campCandidates, campItemName, campRole, canCraft = ns.campCandidates, ns.campItemName, ns.campRole, ns.canCraft
local collectMissing, currentRole, getButton, getRole = ns.collectMissing, ns.currentRole, ns.getButton, ns.getRole
local hasSpellBuff, isSecret, itemKind, knownRecipes = ns.hasSpellBuff, ns.isSecret, ns.itemKind, ns.knownRecipes
local nearCampfire, refreshCooldowns, runPendingCraft, safe = ns.nearCampfire, ns.refreshCooldowns, ns.runPendingCraft, ns.safe
local scanBags, scanRecipes, setPosition, setRole = ns.scanBags, ns.scanRecipes, ns.setPosition, ns.setRole

local function update()
  if InCombatLockdown() then return end -- Secure-Buttons im Kampf nicht anfassen

  local hide = UnitIsDeadOrGhost("player") or UnitOnTaxi("player")
    or (BuffCheckDB.hideMounted and IsMounted())
  local missing = hide and {} or collectMissing()

  local grid = BuffCheckDB.grid
  local gap, perRow = grid.gap, math.max(1, grid.perRow)
  local labels = BuffCheckDB.showLabels
  local stepX = ICON_SIZE + gap
  local stepY = ICON_SIZE + gap + (labels and 14 or 0)

  for i, m in ipairs(missing) do
    local b = getButton(i)
    local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4 + col * stepX, -row * stepY)
    b.icon:SetTexture(m.icon or 134400)
    b.label:SetText(m.text)
    b.label:SetWidth(ICON_SIZE + math.max(gap, 4))
    b.label:SetShown(labels and true or false)
    b.icon:SetDesaturated((m.craft or m.info) and true or false)
    b.icon:SetAlpha((m.craft or m.info) and 0.6 or 1)
    b.craftText:SetShown(BuffCheckDB.showCraftText and (m.craft or m.fresh) and true or false)
    b.glow:Hide() -- kein grüner Rahmen mehr: farbiges Icon = nutzbar
    b.expiresAt = m.expiring and (GetTime() + m.expiring) or nil
    if m.fresh then
      b.craftText:SetText(L["trinken"])
      b.craftText:SetTextColor(0.2, 1, 0.2)
    else
      b.craftText:SetText(L["craften"])
      b.craftText:SetTextColor(1, 0.5, 0.1)
    end
    if m.craft or m.info then
      b.label:SetTextColor(1, 0.5, 0.1)          -- orange = erst herstellen
    else
      b.label:SetTextColor(1, 0.82, 0)           -- normal gelb
    end
    b.text = m.text
    b.hint = m.hint
    b.extra = m.extra
    b.info = m.info
    b.craft = m.craft
    b.craftID = m.craftID
    b.craftLine = m.craftLine
    b.itemID = m.itemID
    b.betterID = m.betterID
    b.weak:SetShown(m.betterID and true or false)
    b.weakArrow:SetShown(m.betterID and true or false)
    -- Zutaten: Anzahl unten rechts, bei 0 rot und kein Herstell-Versuch
    local count = m.craft and m.craftCount or nil
    b.noReagents = count == 0
    if count then
      b.countText:SetText(count)
      if count == 0 then b.countText:SetTextColor(1, 0.25, 0.25) else b.countText:SetTextColor(1, 1, 1) end
      b.countText:Show()
    else
      b.countText:Hide()
    end
    if b.noReagents then
      b.icon:SetVertexColor(1, 0.35, 0.35)
    else
      b.icon:SetVertexColor(1, 1, 1)
    end
    b:SetAttribute("type", nil)
    b:SetAttribute("type1", (not b.noReagents) and m.type or nil)
    b.recipeSpell = m.recipeSpell
    b:SetAttribute("unit", (not m.craft) and "player" or nil)
    b:SetAttribute("spell", m.type == "spell" and m.value or nil)
    b:SetAttribute("item", m.type == "item" and m.value or nil)
    b:SetAttribute("macrotext", m.type == "macro" and m.value or nil)
    -- Woher der Cooldown kommt: Item, Zauber oder Rezept-Zauber
    if m.type == "item" or (m.type == "macro" and m.itemID) then
      b.cdKind, b.cdValue = "item", m.itemID
    elseif m.type == "spell" then
      b.cdKind, b.cdValue = "spell", m.value
    elseif m.recipeSpell then
      b.cdKind, b.cdValue = "spell", m.recipeSpell
    else
      b.cdKind, b.cdValue = nil, nil
    end
    b:Show()
  end
  for i = #missing + 1, #buttons do
    buttons[i]:Hide()
  end
  anchor:Show()
  refreshCooldowns()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
-- Cooldowns direkt nachziehen (ohne komplette Neuprüfung)
local cdWatch = CreateFrame("Frame")
for _, e in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN" }) do
  pcall(cdWatch.RegisterEvent, cdWatch, e)
end
cdWatch:SetScript("OnEvent", function() refreshCooldowns() end)
local pending = false
local function queueUpdate()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false update() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
ev:RegisterEvent("PLAYER_DEAD")
ev:RegisterEvent("PLAYER_UNGHOST")
ev:RegisterUnitEvent("UNIT_AURA", "player")
-- Nicht jede Spielversion kennt alle Events: einzeln absichern
for _, e in ipairs({ "SKILL_LINES_CHANGED", "CHARACTER_POINTS_CHANGED",
  "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP", "TRADE_SKILL_SHOW",
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_UPDATE", "NEW_RECIPE_LEARNED" }) do
  pcall(ev.RegisterEvent, ev, e)
end

local GROUP_DEFAULTS = { essen = true, elixier = true, alchemie = true, lager = true }

ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    BuffCheckDB = BuffCheckDB or {}
    BuffCheckDB.items = BuffCheckDB.items or {}
    BuffCheckDB.ignored = BuffCheckDB.ignored or {}
    BuffCheckDB.enabled = BuffCheckDB.enabled or {}
    if BuffCheckDB.hideMounted == nil then BuffCheckDB.hideMounted = true end
    if BuffCheckDB.alchShowCraft == nil then BuffCheckDB.alchShowCraft = true end
    -- Neuer Standard: alle herstellbaren Elixiere (vorheriges "auto" umstellen)
    if not BuffCheckDB.roleV2 then
      if BuffCheckDB.role == nil or BuffCheckDB.role == "auto" then BuffCheckDB.role = "alle" end
      BuffCheckDB.roleV2 = true
    end
    BuffCheckDB.role = BuffCheckDB.role or "alle"
    for _, g in ipairs(GROUPS) do
      if BuffCheckDB.enabled[g.key] == nil then BuffCheckDB.enabled[g.key] = not g.defaultOff end
    end
    for k, v in pairs(GROUP_DEFAULTS) do
      if BuffCheckDB.enabled[k] == nil then BuffCheckDB.enabled[k] = v end
    end
    if BuffCheckDB.minimap == nil then BuffCheckDB.minimap = { show = true, angle = 220 } end
    BuffCheckDB.grid = BuffCheckDB.grid or {}
    BuffCheckDB.grid.gap = BuffCheckDB.grid.gap or 6
    BuffCheckDB.grid.perRow = BuffCheckDB.grid.perRow or 10
    if BuffCheckDB.showLabels == nil then BuffCheckDB.showLabels = false end
    if BuffCheckDB.showCraftText == nil then BuffCheckDB.showCraftText = false end
    BuffCheckDB.warnBefore = BuffCheckDB.warnBefore or 60
    if BuffCheckDB.alchFallback == nil then BuffCheckDB.alchFallback = true end
    setPosition()
    if ns.OnLoad then ns.OnLoad() end
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then
    if not InCombatLockdown() then anchor:Hide() end
    return
  end
  if event:find("^TRADE_SKILL") or event == "NEW_RECIPE_LEARNED" then
    C_Timer.After(0.5, function()
      if scanRecipes() then queueUpdate() end
      runPendingCraft()
    end)
    return
  end
  queueUpdate()
end)

-- Regelmäßig nachprüfen, damit auslaufende Buffs (< 30 s) auftauchen
C_Timer.NewTicker(5, function() if not InCombatLockdown() then update() end end)

------------------------------------------------------------------------
-- Slash-Befehle: /bc
------------------------------------------------------------------------
local function say(msg) print("|cff33aaffBuffCheck:|r " .. msg) end
local function linkID(s) return tonumber(s:match("item:(%d+)") or s) end
local function groupKeys()
  local keys = {}
  for _, g in ipairs(GROUPS) do table.insert(keys, g.key) end
  for _, k in ipairs({ "essen", "elixier", "alchemie", "lager" }) do table.insert(keys, k) end
  return table.concat(keys, ", ")
end

local function setMoving(unlocked)
  if InCombatLockdown() then return say(L["Im Kampf nicht möglich."]) end
  anchor.unlocked = unlocked
  anchor:EnableMouse(unlocked)
  anchor.bg:SetShown(unlocked)
  anchor:Show()
  say(unlocked and L["Verschieben aktiv – blauen Griff links neben den Icons ziehen."]
    or L["Position gespeichert."])
end

------------------------------------------------------------------------
-- Für Options.lua (Optionsfenster & Minimap-Button) bereitstellen
------------------------------------------------------------------------
ns.GROUPS = GROUPS
ns.ALCH_SLOTS = ALCH_SLOTS
ns.ROLE_SLOTS = ROLE_SLOTS
ns.ROLE_NAMES = ROLE_NAMES
ns.anchor = anchor
ns.say = say
ns.safe = safe
ns.currentRole = currentRole
ns.getRole = getRole
ns.setRole = setRole
ns.CLASS_ROLES = CLASS.roles
ns.alchemySkill = alchemySkill
ns.knownRecipes = knownRecipes
ns.setMoving = setMoving
ns.isMoving = function() return anchor.unlocked end
ns.resetIgnored = function()
  BuffCheckDB.ignored = {}
  wipe(itemKind)
  queueUpdate()
end
ns.rescan = function()
  wipe(itemKind)
  queueUpdate()
end

SLASH_BUFFCHECK1 = "/bc"
SLASH_BUFFCHECK2 = "/buffcheck"
SlashCmdList.BUFFCHECK = function(msg)
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()

  if cmd == "" or cmd == "optionen" or cmd == "options" or cmd == "config" then
    if ns.ToggleOptions then ns.ToggleOptions() end
  elseif cmd == "minimap" then
    BuffCheckDB.minimap.show = true
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    say(L["Minimap-Button wird wieder angezeigt."])
  elseif cmd == "move" then
    setMoving(not anchor.unlocked)
  elseif cmd == "item" then
    local id = linkID(rest)
    if not id then return say(L["Benutzung: /bc item [Item shift-klicken]"]) end
    BuffCheckDB.items[id] = true
    BuffCheckDB.ignored[id] = nil
    say(L["Überwache immer: %s"]:format(safe(C_Item.GetItemNameByID, id) or id))
    queueUpdate()
  elseif cmd == "food" then
    local id = linkID(rest)
    if not id then return say(L["Benutzung: /bc food [Essen shift-klicken]"]) end
    BuffCheckDB.food = id
    say(L["Bevorzugtes Essen: %s"]:format(safe(C_Item.GetItemNameByID, id) or id))
    queueUpdate()
  elseif cmd == "ignore" then
    local id = linkID(rest)
    if id then BuffCheckDB.ignored[id] = true say(L["Ignoriert."]) queueUpdate() end
  elseif cmd == "reset" then
    BuffCheckDB.ignored = {}
    wipe(itemKind)
    say(L["Ignorierliste geleert."])
    queueUpdate()
  elseif cmd == "toggle" then
    local key = rest:lower()
    if BuffCheckDB.enabled[key] == nil then return say(L["Gruppen: %s"]:format(groupKeys())) end
    BuffCheckDB.enabled[key] = not BuffCheckDB.enabled[key]
    say(key .. ": " .. (BuffCheckDB.enabled[key] and L["an"] or L["aus"]))
    queueUpdate()
  elseif cmd == "alch" or cmd == "alchemie" then
    local arg = rest:lower()
    if arg == "" then
      BuffCheckDB.enabled.alchemie = not BuffCheckDB.enabled.alchemie
      say(L["Alchemie-Buffs als gebraucht: "] .. (BuffCheckDB.enabled.alchemie and L["an"] or L["aus"]))
    elseif arg == "tasche" then
      BuffCheckDB.alchShowCraft = not BuffCheckDB.alchShowCraft
      say(L["Auch nicht vorrätige (graue) Tränke zeigen: "] .. (BuffCheckDB.alchShowCraft and L["an"] or L["aus"]))
    elseif ALCH_SLOTS[arg] then
      local k = "alch_" .. arg
      BuffCheckDB.enabled[k] = BuffCheckDB.enabled[k] == false
      say("Slot " .. arg .. ": " .. (BuffCheckDB.enabled[k] and L["an"] or L["aus"]))
    elseif arg == "info" then
      local role = currentRole()
      say((L["Alchemie-Skill: %d, Rolle: %s%s"]):format(alchemySkill(), ROLE_NAMES[role],
        getRole() == "auto" and L[" (automatisch)"] or ""))
      for _, key in ipairs(ROLE_SLOTS[role]) do
        local best
        for _, e in ipairs(ALCH_SLOTS[key].list) do
          if canCraft(e, alchemySkill()) then best = best or e end
        end
        local off = BuffCheckDB.enabled["alch_" .. key] == false and L[" [aus]"] or ""
        say(("  %s (%s): %s%s"):format(ALCH_SLOTS[key].label, key,
          best and (safe(C_Item.GetItemNameByID, best[1]) or best[1]) or L["nichts herstellbar"], off))
      end
    else
      local keys = {}
      for k in pairs(ALCH_SLOTS) do table.insert(keys, k) end
      table.sort(keys)
      say("/bc alch | alch info | alch tasche | alch <" .. table.concat(keys, "|") .. ">")
    end
    queueUpdate()
  elseif cmd == "craftdebug" then
    -- Zeigt, womit die Craft-Icons belegt sind (zur Fehlersuche)
    say("KeyDown: " .. tostring(GetCVar and GetCVar("ActionButtonUseKeyDown")))
    local any = false
    for i, b in ipairs(buttons) do
      if b:IsShown() and b.craftID then
        any = true
        local rid = (knownRecipes() or {})[b.craftID]
        local info = b.recipeSpell and safe(C_Spell.GetSpellInfo, b.recipeSpell)
        say(("#%d %s | type1=%s spell=%s unit=%s | Rezept-ID=%s | Zauber per Name bekannt=%s | IsSpellKnown=%s"):format(
          i, tostring(b.recipeSpell), tostring(b:GetAttribute("type1")), tostring(b:GetAttribute("spell")),
          tostring(b:GetAttribute("unit")), tostring(rid), info and tostring(info.spellID) or "nein",
          tostring(type(rid) == "number" and IsSpellKnown and IsSpellKnown(rid))))
        say("   Test: /click BuffCheckButton" .. i)
      end
    end
    if not any then say("Keine Craft-Icons sichtbar.") end
  elseif cmd == "lager" or cmd == "camp" then
    -- Zeigt, ob ein Lagerfeuer erkannt wird und welches Objekt vorgeschlagen wird
    local near, why = nearCampfire()
    say(L["Lagerfeuer in der Nähe: %s"]:format(near and (L["ja"] .. " (" .. why .. ")") or L["nein"]))
    say(L["Rolle für Lagerobjekte: %s"]:format(ROLE_NAMES[campRole()] or campRole()))
    local cAura, cText = campBuff()
    if cAura then
      say(L["Lager-Buff: %s | Tooltip: %s"]:format(cAura.name or "?",
        (cText and cText ~= "") and cText:gsub("\n", " / ") or L["nicht lesbar"]))
    end
    local blocked = {}
    for n in pairs(campBlockedSpells()) do table.insert(blocked, n) end
    table.sort(blocked)
    say(L["Vom Lager-Buff blockiert: %s"]:format(#blocked > 0 and table.concat(blocked, ", ") or "-"))
    local list = campCandidates()
    if #list == 0 then say(L["Kein Lagerobjekt in der Tasche und kein passender Beruf."]) end
    for _, c in ipairs(list) do
      local id = c.have or c.obj.items[#c.obj.items]
      say(("  %s – %s | %s%s%s"):format(campItemName(id), c.obj.effect,
        c.have and L["in der Tasche"] or L["herstellen"],
        c.skill > 0 and (" | Skill " .. c.skill) or "",
        c.blockedBy and (" | " .. L["wirkt nicht mit %s"]:format(c.blockedBy)) or "")
        .. (c.inCamp and (" | " .. L["steht schon im Lager"]) or ""))
    end
    local auras = {}
    for i = 1, 40 do
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if not ok or not a then break end
      if not isSecret(a) and a.name and not isSecret(a.name) then
        table.insert(auras, a.name .. (a.spellId and not isSecret(a.spellId) and (" #" .. a.spellId) or ""))
      end
    end
    say(L["Deine Buffs: %s"]:format(#auras > 0 and table.concat(auras, ", ") or "-"))
  elseif cmd == "debug" then
    local skill = alchemySkill()
    local role = currentRole()
    say(("Debug: Alchemie-Skill %d, Rolle %s, Alchemie %s, Kampf %s, Client %s"):format(
      skill, role, BuffCheckDB.enabled.alchemie and L["an"] or L["aus"],
      InCombatLockdown() and "ja" or "nein", GetLocale and GetLocale() or "?"))
    say(knownRecipes() and L["Rezepte: aus Alchemie-Fenster gemerkt"] or L["Rezepte: noch nicht gescannt (Alchemie-Fenster einmal öffnen) – schätze nach Skill"])
    for _, key in ipairs(ROLE_SLOTS[role]) do
      say("Slot " .. key .. (BuffCheckDB.enabled["alch_" .. key] == false and L[" [aus]"] or ""))
      for _, e in ipairs(ALCH_SLOTS[key].list) do
        local s = hasSpellBuff(e[2], e[1])
        local name = safe(C_Item.GetItemNameByID, e[1]) or ("Item " .. e[1])
        local buffName = safe(C_Spell.GetSpellName, e[2]) or safe(C_Item.GetItemSpell, e[1]) or "?"
        say(("   %s | Skill %d%s | Tasche %d | Buff '%s' = %s"):format(name, e[3],
          canCraft(e, skill) and "" or L[" (nicht herstellbar)"], safe(C_Item.GetItemCount, e[1]) or 0,
          buffName, s == nil and L["unlesbar"] or tostring(s)))
      end
    end
    local ok, err = pcall(collectMissing)
    say(ok and L["Prüfung: %d Einträge fehlen"]:format(#err) or L["Prüfung: FEHLER: %s"]:format(tostring(err)))
  elseif cmd == "rolle" or cmd == "role" then
    local r = rest:lower()
    if not CLASS_ROLE[r] then return say("Benutzung: /bc rolle <alle|auto|" .. table.concat(CLASS.roles, "|") .. ">") end
    setRole(r)
    say("Rolle: " .. (r == "auto" and "automatisch (" .. ROLE_NAMES[currentRole()] .. ")" or ROLE_NAMES[r]))
    queueUpdate()
  elseif cmd == "mount" then
    BuffCheckDB.hideMounted = not BuffCheckDB.hideMounted
    say(L["Auf Reittier ausblenden: "] .. (BuffCheckDB.hideMounted and L["an"] or L["aus"]))
    queueUpdate()
  elseif cmd == "list" then
    for k, v in pairs(BuffCheckDB.enabled) do say(k .. " = " .. (v and L["an"] or L["aus"])) end
    for id in pairs(BuffCheckDB.ignored) do
      say(L["Ignoriert: %s"]:format(safe(C_Item.GetItemNameByID, id) or id))
    end
  elseif cmd == "scan" then
    wipe(itemKind)
    local foods, buffs = scanBags()
    for _, id in ipairs(foods) do say(L["Essen: %s"]:format(safe(C_Item.GetItemNameByID, id) or id)) end
    for id in pairs(buffs) do say("Buff-Item: " .. (safe(C_Item.GetItemNameByID, id) or id)) end
  else
    say(L["/bc öffnet die Optionen (auch über den Minimap-Button)."])
    say(L["Weitere: /bc move | minimap | food [Link] | item [Link] | ignore [Link] | lager | debug"])
  end
end
