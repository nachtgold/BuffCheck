-- BuffCheck – Alchemie: Daten, Rezepte, Herstellen per Klick

local ADDON, ns = ...
local L = ns.L

local hasSpellBuff, inBags, isSecret, levelOK = ns.hasSpellBuff, ns.inBags, ns.isSecret, ns.levelOK
local safe = ns.safe

------------------------------------------------------------------------
-- Alchemie: Tränke/Elixiere/Fläschchen, die du selbst herstellen kannst,
-- gelten je nach Rolle als "gebraucht". Daten: wowhead.com/forever
-- (Alchemie-Rezepte, Stand 05.11.2026). Format: { Item-ID, Buff-Spell-ID, Skill }
-- Pro Slot: bestes zuerst. Ein Slot ist erfüllt, wenn IRGENDEIN Buff
-- der Liste aktiv ist; er erscheint nur, wenn dein Skill für mindestens
-- einen Eintrag reicht.
------------------------------------------------------------------------
local ALCHEMY_SKILLLINE = 171
local ALCHEMY_NAMES = { alchemie = true, alchemy = true }

local ALCH_SLOTS = {
  flask_heal = { label = L["Fläschchen"], list = {
    { 13511, 17627, 300 }, -- Fläschchen der destillierten Weisheit (+2000 Mana, 2 Std.)
  } },
  flask_tank = { label = L["Fläschchen"], list = {
    { 13510, 17626, 300 }, -- Fläschchen der Titanen (+1200 Leben, 2 Std.)
  } },
  flask_caster = { label = L["Fläschchen"], list = {
    { 13512, 17628, 300 }, -- Fläschchen der obersten Macht (+150 Zauberschaden, 2 Std.)
  } },
  heilung = { label = L["Heilung"], list = {
    { 250333, 1250926, 195 }, -- Großes Klerikerelixier (+40 Heilung)
    { 250332, 1250925, 145 }, -- Klerikerelixier (+30)
    { 250331, 1250924, 95 },  -- Geringes Klerikerelixier (+20)
    { 250330, 1250922, 45 },  -- Schwaches Klerikerelixier (+10)
  } },
  manareg = { label = L["Mana-Reg."], list = {
    { 250341, 1250948, 175 }, -- Großes Magierblutelixier (20 Mana/5s)
    { 20007, 24363, 275 },    -- Magierblutelixier (12 Mana/5s, 1 Std.)
    { 250336, 1250932, 285 }, -- Elixier der üblen Regeneration (10 Mana + 9 Leben/5s)
    { 250340, 1250944, 75 },  -- Geringes Magierblutelixier (6)
    { 250339, 1250942, 25 },  -- Schwaches Magierblutelixier (3)
  } },
  int = { label = L["Intelligenz"], list = {
    { 250337, 1250940, 280 }, -- Elixier der Eule (+25 Int, 2 % Krit)
    { 9179, 11396, 235 },     -- Elixier der großen Intelligenz (+25)
    { 250328, 1250918, 275 }, -- Elixier der Gerissenheit (+25 Bew. & Int)
    { 13447, 17535, 270 },    -- Elixier der Weisen (+18 Int & Wil)
    { 250354, 1250989, 135 }, -- Elixier der Intelligenz (+10)
    { 250353, 1250988, 95 },  -- Elixier der geringen Intelligenz (+6)
    { 3383, 3166, 90 },       -- Elixier der Weisheit (+3)
  } },
  leben = { label = L["Gesundheit"], list = {
    { 250329, 1250920, 250 }, -- Elixier der Phalanx (+400 Leben, +500 Rüstung)
    { 250335, 1250931, 200 }, -- Elixier der großen Seelenstärke (+400)
    { 250334, 1250928, 150 }, -- Elixier der Seelenstärke (+200)
    { 3825, 3593, 175 },      -- Elixier der geringen Seelenstärke (+120)
    { 2458, 2378, 50 },       -- Elixier der schwachen Seelenstärke (+27)
  } },
  ruestung = { label = L["Rüstung"], list = {
    { 13445, 11348, 265 },    -- Elixier der großen Verteidigung (+450)
    { 8951, 11349, 195 },     -- Elixier der Verteidigung (+250)
    { 3389, 3220, 130 },      -- Elixier der geringen Verteidigung (+150)
    { 5997, 673, 55 },        -- Elixier der schwachen Verteidigung (+50)
  } },
  staerke = { label = L["Stärke"], list = {
    { 250351, 1250986, 300 }, -- Elixier des Grizzlys (+25 Str, 2 % Krit)
    { 9206, 11405, 245 },     -- Elixier der großen Stärke (+25)
    { 250350, 1250985, 275 }, -- Elixier der Wildheit (+18 Str & Bew)
    { 13453, 17537, 275 },    -- Elixier der rohen Gewalt (+18 Str & Ausd)
    { 250349, 1250984, 150 }, -- Elixier der Stärke (+10)
    { 3391, 3164, 150 },      -- Elixier der Ogerstärke (+8)
    { 2454, 2367, 15 },       -- Elixier der schwachen Stärke (+4)
  } },
  bew = { label = L["Beweglichk."], list = {
    { 13452, 17538, 280 },    -- Elixier des Mungos (+25 Bew, 2 % Krit)
    { 9187, 11334, 240 },     -- Elixier der großen Beweglichkeit (+25)
    { 250328, 1250918, 275 }, -- Elixier der Gerissenheit (+25 Bew & Int)
    { 250350, 1250985, 275 }, -- Elixier der Wildheit (+18 Str & Bew)
    { 8949, 11328, 185 },     -- Elixier der Beweglichkeit (+15)
    { 3390, 3160, 140 },      -- Elixier der geringen Beweglichkeit (+8)
    { 2457, 2374, 50 },       -- Elixier der schwachen Beweglichkeit (+4)
  } },
  flask = { label = L["Fläschchen"], list = {
    { 13510, 17626, 300 }, -- Fläschchen der Titanen
    { 13511, 17627, 300 }, -- Fläschchen der destillierten Weisheit
    { 13512, 17628, 300 }, -- Fläschchen der obersten Macht
  } },
  regen = { label = L["Leben-Reg."], list = {
    { 20004, 24361, 290 },    -- Elixier des großen Trollbluts (20 Leben/5s, 1 Std.)
    { 3826, 3223, 180 },      -- Trollblutelixier (12)
    { 3388, 3222, 125 },      -- Geringes Trollblutelixier (6)
    { 3382, 3219, 15 },       -- Schwaches Trollblutelixier (2)
  } },
  zauber = { label = L["Zauberschaden"], list = {
    { 13454, 17539, 285 },    -- Großes arkanes Elixier (+35)
    { 9155, 11390, 235 },     -- Arkanes Elixier (+20)
    { 250342, 1250971, 120 }, -- Geringes arkanes Elixier (+15)
    { 247754, 1245244, 10 },  -- Schwaches arkanes Elixier (+5)
  } },
  angriff = { label = L["Angriffskr."], list = {
    { 246948, 17038, 250 },   -- Destilliertes Feuerwasser (+35 AK, 20 Min.)
    { 247755, 1245249, 10 },  -- Elixier der schwachen Kraft (+1 phys. Schaden, 30 Min.)
  } },
}

-- Welche Slots pro Rolle gebraucht werden (Reihenfolge = Anzeige)
local ROLE_SLOTS = {
  heal = { "flask_heal", "heilung", "manareg", "int" },
  tank = { "flask_tank", "leben", "ruestung", "staerke" },
  dd   = { "flask_tank", "staerke", "bew", "angriff" },
  caster = { "flask_caster", "zauber", "int", "manareg" },
  alle = { "flask", "staerke", "bew", "angriff", "zauber", "leben", "ruestung",
           "regen", "heilung", "manareg", "int" },
}
local ROLE_NAMES = { heal = L["Heiler"], tank = L["Tank"], dd = L["Nahkampf"], caster = L["Zauberer"],
  alle = L["alle (jedes herstellbare Elixier)"] }

-- Alle Item-IDs, die zu einem Slot gehören (für den Rezept-Scan)
local ALCH_ITEMS = {}
for _, slot in pairs(ALCH_SLOTS) do
  for _, e in ipairs(slot.list) do ALCH_ITEMS[e[1]] = true end
end
-- Alle Fläschchen schließen sich gegenseitig aus: jedes aktive zählt als erfüllt
local ANY_FLASK = { 13510, 13511, 13512, 13513, 274273, 274274, 274275, 274276 }

------------------------------------------------------------------------
-- Bekannte Rezepte: werden beim Öffnen des Alchemie-Fensters gemerkt
-- (pro Charakter). Ohne Scan wird nach Skillstufe geschätzt.
------------------------------------------------------------------------
local function charKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

local function knownRecipes()
  return BuffCheckDB.known and BuffCheckDB.known[charKey()]
end

-- Rezepte für Lagerobjekte (aus jedem Berufsfenster, wird ergänzt statt ersetzt)
local function campRecipes()
  BuffCheckDB.knownCamp = BuffCheckDB.knownCamp or {}
  local k = charKey()
  BuffCheckDB.knownCamp[k] = BuffCheckDB.knownCamp[k] or {}
  return BuffCheckDB.knownCamp[k]
end

-- Rezept-ID zu einem Item (Alchemie oder Lagerobjekt), nil = unbekannt
local function recipeFor(itemID)
  local rid = (knownRecipes() or {})[itemID]
  if rid == nil then rid = campRecipes()[itemID] end
  return rid
end

local function itemFromLink(link)
  if type(link) ~= "string" or isSecret(link) then return nil end
  return tonumber(link:match("item:(%d+)"))
end

local tradeIndexOf = {} -- itemID -> Index im Berufsfenster (alte API, nur diese Sitzung)
local justCrafted = {}  -- itemID -> true: frisch hergestellt, jetzt trinken

local function chat(msg) print("|cff33aaffBuffCheck:|r " .. msg) end

-- Zutaten eines Rezepts aus der Rezeptdatenbank des Spiels: { {itemID, menge}, ... }
local function schematicReagents(rid)
  local T = C_TradeSkillUI
  if not (T and T.GetRecipeSchematic and rid) then return nil end
  local sch = safe(T.GetRecipeSchematic, rid, false)
  if type(sch) ~= "table" or type(sch.reagentSlotSchematics) ~= "table" then return nil end
  local out = {}
  for _, slot in ipairs(sch.reagentSlotSchematics) do
    local r = slot.reagents and slot.reagents[1]
    local basic = slot.reagentType == nil or slot.reagentType == 1 -- 1 = Grundzutat
    local qty = slot.quantityRequired
    if r and r.itemID and basic and slot.required ~= false and type(qty) == "number" and qty > 0 then
      table.insert(out, { r.itemID, qty })
    end
  end
  return #out > 0 and out or nil
end

local function scanRecipes()
  local found, reagents, any, campAny = {}, {}, false, false
  local T = C_TradeSkillUI
  -- Lagerobjekte aus dem gerade offenen Berufsfenster merken
  if T and T.GetAllRecipeIDs then
    local camp = campRecipes()
    for _, rid in ipairs(safe(T.GetAllRecipeIDs) or {}) do
      local info = safe(T.GetRecipeInfo, rid)
      if info and info.learned then
        local sch = T.GetRecipeSchematic and safe(T.GetRecipeSchematic, rid, false)
        local itemID = sch and sch.outputItemID
        if not itemID and T.GetRecipeItemLink then itemID = itemFromLink(safe(T.GetRecipeItemLink, rid)) end
        if itemID and ns.CAMP_ITEM[itemID] then
          camp[itemID] = rid
          campAny = true
          local list = schematicReagents(rid)
          if list then
            BuffCheckDB.reagents = BuffCheckDB.reagents or {}
            BuffCheckDB.reagents[itemID] = list
          end
        end
      end
    end
  end
  if T and T.GetAllRecipeIDs then
    local ids = safe(T.GetAllRecipeIDs)
    for _, rid in ipairs(ids or {}) do
      local info = safe(T.GetRecipeInfo, rid)
      if info and info.learned then
        local itemID
        if T.GetRecipeSchematic then
          local sch = safe(T.GetRecipeSchematic, rid, false)
          itemID = sch and sch.outputItemID
        end
        if not itemID and T.GetRecipeItemLink then itemID = itemFromLink(safe(T.GetRecipeItemLink, rid)) end
        if itemID and ALCH_ITEMS[itemID] then
          found[itemID] = rid
          reagents[itemID] = schematicReagents(rid)
          any = true
        end
      end
    end
  end
  if not any and GetNumTradeSkills and GetTradeSkillItemLink then
    for i = 1, (safe(GetNumTradeSkills) or 0) do
      local _, kind = safe(GetTradeSkillInfo, i)
      if kind ~= "header" then
        local itemID = itemFromLink(safe(GetTradeSkillItemLink, i))
        if itemID and ALCH_ITEMS[itemID] then
          found[itemID] = true
          tradeIndexOf[itemID] = i
          any = true
          -- alte API: Zutaten nur bei offenem Fenster lesbar
          if GetTradeSkillNumReagents and GetTradeSkillReagentInfo and GetTradeSkillReagentItemLink then
            local list = {}
            for r = 1, (safe(GetTradeSkillNumReagents, i) or 0) do
              local _, _, need = safe(GetTradeSkillReagentInfo, i, r)
              local rid = itemFromLink(safe(GetTradeSkillReagentItemLink, i, r))
              if rid and type(need) == "number" then table.insert(list, { rid, need }) end
            end
            if #list > 0 then reagents[itemID] = list end
          end
        end
      end
    end
  end
  -- Nur übernehmen, wenn es wirklich das Alchemie-Fenster war
  if any then
    BuffCheckDB.known = BuffCheckDB.known or {}
    BuffCheckDB.known[charKey()] = found
    BuffCheckDB.reagents = BuffCheckDB.reagents or {}
    for id, list in pairs(reagents) do BuffCheckDB.reagents[id] = list end
  end
  return any or campAny
end

-- Zutatenliste eines Tranks (gemerkt oder live aus der Rezeptdatenbank)
local function reagentsFor(itemID)
  local list = BuffCheckDB.reagents and BuffCheckDB.reagents[itemID]
  if list then return list end
  local rid = recipeFor(itemID)
  if type(rid) == "number" then
    list = schematicReagents(rid)
    if list then
      BuffCheckDB.reagents = BuffCheckDB.reagents or {}
      BuffCheckDB.reagents[itemID] = list
    end
  end
  return list
end

-- Wie oft kannst du ihn mit deinen Zutaten herstellen? nil = unbekannt
local function craftCount(itemID)
  local list = reagentsFor(itemID)
  if not list then return nil end
  local n = math.huge
  for _, r in ipairs(list) do
    local have = safe(C_Item.GetItemCount, r[1]) or 0
    n = math.min(n, math.floor(have / r[2]))
  end
  return n
end

------------------------------------------------------------------------
-- Herstellen per Klick: öffnet bei Bedarf das Alchemie-Fenster und
-- stellt einen Trank her. Trinken braucht danach einen zweiten Klick
-- (Blizzard erlaubt Addons das Benutzen von Items nur per Klick).
------------------------------------------------------------------------
local pendingCraft

-- Ist das Fenster dieses Berufs offen? (Standard: Alchemie)
local function windowOpen(line)
  line = line or ALCHEMY_SKILLLINE
  local T = C_TradeSkillUI
  if T and T.IsTradeSkillReady and not safe(T.IsTradeSkillReady) then return false end
  if T and T.GetBaseProfessionInfo then
    local info = safe(T.GetBaseProfessionInfo)
    if info and info.professionID == line then return true end
  end
  if T and T.GetTradeSkillLine then
    if safe(T.GetTradeSkillLine) == line then return true end
  end
  if line == ALCHEMY_SKILLLINE and GetTradeSkillLine then
    local name = safe(GetTradeSkillLine)
    if type(name) == "string" and ALCHEMY_NAMES[name:lower()] then return true end
  end
  return false
end
local function alchemyWindowOpen() return windowOpen(ALCHEMY_SKILLLINE) end

-- true = Herstellen gestartet (oder sinnvoll abgebrochen), false = ging nicht
local function doCraft(itemID)
  local name = safe(C_Item.GetItemNameByID, itemID) or ("Item " .. itemID)
  local T = C_TradeSkillUI
  local rid = recipeFor(itemID)
  if type(rid) ~= "number" then rid = nil end
  if T and T.CraftRecipe and rid then
    local info = safe(T.GetRecipeInfo, rid)
    if info and type(info.numAvailable) == "number" and info.numAvailable < 1 then
      chat(L["Zutaten fehlen für %s."]:format(name))
      return true
    end
    if pcall(T.CraftRecipe, rid, 1) then
      justCrafted[itemID] = true
      return true
    end
  end
  local idx = tradeIndexOf[itemID]
  if DoTradeSkill and idx then
    local _, _, avail = safe(GetTradeSkillInfo, idx)
    if type(avail) == "number" and avail < 1 then
      chat(L["Zutaten fehlen für %s."]:format(name))
      return true
    end
    if pcall(DoTradeSkill, idx, 1) then
      justCrafted[itemID] = true
      return true
    end
  end
  return false
end

-- Merkt, ob nach einem Klick der Rezept-Zauber wirklich gestartet ist
local craftCast = {}
local castWatch = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
  pcall(castWatch.RegisterUnitEvent, castWatch, e, "player")
end
castWatch:SetScript("OnEvent", function(_, event, _, a2, a3, a4)
  -- Herstellen fertig: Alchemie-Fenster wieder zu
  if event == "UNIT_SPELLCAST_SUCCEEDED" and craftCast.closeWindow then
    craftCast.closeWindow = nil
    local T = C_TradeSkillUI
    if T and T.CloseTradeSkill then pcall(T.CloseTradeSkill)
    elseif CloseTradeSkill then pcall(CloseTradeSkill) end
  end
  -- Irgendein eigener Zauber kurz nach dem Klick = das Rezept wurde gewirkt
  if craftCast.spell then craftCast.started = true end
end)

-- Nur direkt aus einem Klick aufrufen: Herstellen/Fenster öffnen ist geschützt
-- und wird blockiert, wenn es aus einem Timer oder Event heraus passiert.
local function noWindowMsg(line)
  if line and line ~= ALCHEMY_SKILLLINE then
    return L["Bitte das Berufsfenster öffnen und dann nochmal auf das Icon klicken."]
  end
  return L["Bitte das Alchemie-Fenster öffnen und dann nochmal auf das Icon klicken."]
end

local function craftItem(itemID, line)
  if InCombatLockdown() then return end
  line = line or ALCHEMY_SKILLLINE
  if windowOpen(line) and doCraft(itemID) then
    craftCast.closeWindow = true -- nach dem Herstellen Fenster wieder schließen
    return
  end
  local T = C_TradeSkillUI
  local rid = recipeFor(itemID)
  -- Fenster gleich beim richtigen Rezept öffnen, sonst nur das Fenster
  local opened = (T and T.OpenRecipe and type(rid) == "number" and pcall(T.OpenRecipe, rid))
    or (T and T.OpenTradeSkill and pcall(T.OpenTradeSkill, line))
  if not opened then
    chat(noWindowMsg(line))
    return
  end
  -- Rezept noch nie gesehen (z. B. Lagerobjekt)? Jetzt im offenen Fenster suchen
  if type(rid) ~= "number" and windowOpen(line) then scanRecipes() end
  -- Sind die Rezeptdaten sofort da, gleich im selben Klick herstellen
  if windowOpen(line) and doCraft(itemID) then
    craftCast.closeWindow = true
    return
  end
  pendingCraft = itemID -- sonst: nächster Klick stellt her
end

-- Nach dem Öffnen des Fensters: nur Bescheid geben (Herstellen braucht einen Klick)
local function runPendingCraft()
  if not pendingCraft or not alchemyWindowOpen() then return end
  pendingCraft = nil
  chat(L["Alchemie-Fenster offen – nochmal auf das Icon klicken zum Herstellen."])
end

-- Meldet, wenn WoW eine Aktion dieses Addons blockiert (zur Fehlersuche)
local blockWatch = CreateFrame("Frame")
pcall(blockWatch.RegisterEvent, blockWatch, "ADDON_ACTION_BLOCKED")
pcall(blockWatch.RegisterEvent, blockWatch, "ADDON_ACTION_FORBIDDEN")
blockWatch:SetScript("OnEvent", function(_, event, addon, func)
  if addon == ADDON then
    chat("|cffff5555" .. L["WoW hat blockiert:"] .. "|r " .. tostring(func) .. " (" .. event .. ")")
  end
end)

-- Kannst du diesen Eintrag herstellen?
local function canCraft(e, skill)
  local known = knownRecipes()
  if known then return known[e[1]] and true or false end
  return e[3] <= skill
end

-- Liefert fehlende Alchemie-Slots und die Item-IDs, die hier schon behandelt sind
local function collectAlchemy(missing)
  local handled = {}
  local skill = ns.alchemySkill()
  if skill <= 0 and not knownRecipes() then return handled end
  local role = ns.currentRole()
  for _, key in ipairs(ROLE_SLOTS[role]) do
    local slot = ALCH_SLOTS[key]
    if BuffCheckDB.enabled["alch_" .. key] ~= false then
      -- Bestes herstellbares Rezept – bevorzugt eines, für das du Zutaten hast
      local craftable, withReagents
      for _, e in ipairs(slot.list) do
        if canCraft(e, skill) and levelOK(e[1]) then
          craftable = craftable or e
          if not withReagents and (craftCount(e[1]) or 0) > 0 then withReagents = e end
        end
      end
      -- Schwächeres Rezept als Ersatz nur, wenn erlaubt (Einstellung)
      local betterID
      if withReagents and withReagents ~= craftable and BuffCheckDB.alchFallback
        and craftCount(craftable[1]) == 0 then -- nur wenn beim besten sicher Zutaten fehlen
        betterID = craftable[1]
        craftable = withReagents
      end
      if craftable then
        -- erfüllt?
        local active, unreadable = false, false
        local check = slot.list
        if key:find("^flask") then
          check = {}
          for _, id in ipairs(ANY_FLASK) do table.insert(check, { id }) end
          for _, e in ipairs(slot.list) do table.insert(check, e) end
        end
        for _, e in ipairs(check) do handled[e[1]] = true end
        local expiring
        for _, e in ipairs(check) do
          local s, rem = hasSpellBuff(e[2], e[1])
          if s then active = true break end
          if s == nil then unreadable = true end
          if rem then expiring = math.max(expiring or 0, rem) end
        end

        if active then
          for _, e in ipairs(slot.list) do justCrafted[e[1]] = nil end
        elseif not unreadable then
          local have
          for _, e in ipairs(slot.list) do
            if inBags(e[1]) and levelOK(e[1]) then have = e break end
          end
          if have then
            table.insert(missing, {
              text = slot.label, icon = safe(C_Item.GetItemIconByID, have[1]),
              type = "item", value = "item:" .. have[1], itemID = have[1],
              hint = safe(C_Item.GetItemNameByID, have[1]), expiring = expiring,
              fresh = justCrafted[have[1]],
            })
          elseif BuffCheckDB.alchShowCraft then
            local id = craftable[1]
            local name = safe(C_Item.GetItemNameByID, id) or ("Item " .. id)
            -- Herstellen per "/cast <Rezeptname>" (geht ohne Handwerksfenster).
            -- Rezeptname = Zaubername des Rezepts, sonst der Itemname.
            local rid = (knownRecipes() or {})[id]
            local recipeName = type(rid) == "number" and safe(C_Spell.GetSpellName, rid) or nil
            recipeName = recipeName or safe(C_Item.GetItemNameByID, id)
            table.insert(missing, {
              text = slot.label, icon = safe(C_Item.GetItemIconByID, id),
              itemID = nil, craft = true, craftID = id,
              -- Rezepte lassen sich in Forever nicht als Zauber wirken (weder per
              -- Name noch per ID). Herstellen läuft übers Handwerksfenster.
              type = nil, value = nil,
              hint = (knownRecipes() and L["Herstellen: %s (Rezept bekannt) – nicht in der Tasche"]:format(name)
                or L["Herstellen: %s (ab Alchemie %d) – nicht in der Tasche"]:format(name, craftable[3])),
              expiring = expiring,
              craftCount = craftCount(id),
              betterID = betterID, -- gesetzt = das hier ist nur der schwächere Ersatz
            })
          end
        end
      end
    end
  end
  return handled
end

-- Rechtsklick auf ein Craft-Icon: Alchemie-Fenster beim Rezept öffnen
local function openRecipe(itemID, line)
  if InCombatLockdown() then return end
  local T = C_TradeSkillUI
  local rid = recipeFor(itemID)
  if T and T.OpenRecipe and type(rid) == "number" and pcall(T.OpenRecipe, rid) then return end
  if T and T.OpenTradeSkill and pcall(T.OpenTradeSkill, line or ALCHEMY_SKILLLINE) then
    -- alte Fenster: Rezept auswählen, sobald die Liste da ist
    local idx = tradeIndexOf[itemID]
    if idx and SelectTradeSkill then C_Timer.After(0.2, function() pcall(SelectTradeSkill, idx) end) end
    return
  end
  chat(noWindowMsg(line))
end

-- Für die anderen Module
ns.ALCHEMY_SKILLLINE = ALCHEMY_SKILLLINE
ns.ALCHEMY_NAMES = ALCHEMY_NAMES
ns.ALCH_SLOTS = ALCH_SLOTS
ns.ROLE_SLOTS = ROLE_SLOTS
ns.ROLE_NAMES = ROLE_NAMES
ns.ALCH_ITEMS = ALCH_ITEMS
ns.ANY_FLASK = ANY_FLASK
ns.charKey = charKey
ns.knownRecipes = knownRecipes
ns.campRecipes = campRecipes
ns.recipeFor = recipeFor
ns.itemFromLink = itemFromLink
ns.tradeIndexOf = tradeIndexOf
ns.justCrafted = justCrafted
ns.chat = chat
ns.schematicReagents = schematicReagents
ns.scanRecipes = scanRecipes
ns.reagentsFor = reagentsFor
ns.craftCount = craftCount
ns.windowOpen = windowOpen
ns.alchemyWindowOpen = alchemyWindowOpen
ns.doCraft = doCraft
ns.craftCast = craftCast
ns.noWindowMsg = noWindowMsg
ns.craftItem = craftItem
ns.runPendingCraft = runPendingCraft
ns.canCraft = canCraft
ns.collectAlchemy = collectAlchemy
ns.openRecipe = openRecipe
