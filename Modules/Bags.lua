-- BuffCheck – Taschen-Scan: Buff-Essen und Verbrauchsgüter mit langer Wirkung

local ADDON, ns = ...
local L = ns.L

local MIN_BUFF_MINUTES, isSecret, safe = ns.MIN_BUFF_MINUTES, ns.isSecret, ns.safe

-- Name des Essens-Buffs (deutsch / englisch)
local WELL_FED = { "Satt", "Well Fed" }
-- Textstellen im Tooltip, an denen Buff-Essen erkannt wird
local FOOD_PATTERNS = { "satt", "well fed" }

------------------------------------------------------------------------
-- Taschen-Scan: erkennt Buff-Essen und Verbrauchsgüter mit langer Wirkung
------------------------------------------------------------------------
local itemKind = {} -- Cache: itemID -> "food" | "buff" | false

local function tooltipLines(bag, slot)
  local data = safe(C_TooltipInfo and C_TooltipInfo.GetBagItem, bag, slot)
  local out = {}
  if data and data.lines then
    for _, l in ipairs(data.lines) do
      local t = l.leftText
      if t and not isSecret(t) then table.insert(out, t:lower()) end
    end
  end
  return out
end

local function longDuration(line)
  line = line:gsub("%b()", "") -- "(2 Min. Abklingzeit)" entfernen
  if line:find("std%.") or line:find("stunde") or line:find("hour") then return true end
  for n in line:gmatch("(%d+)%s*min") do
    if tonumber(n) >= MIN_BUFF_MINUTES then return true end
  end
  return false
end

local function classify(itemID, bag, slot)
  if itemKind[itemID] ~= nil then return itemKind[itemID] end
  local _, _, _, _, _, classID = safe(C_Item.GetItemInfoInstant, itemID)
  local consumable = Enum and Enum.ItemClass and Enum.ItemClass.Consumable or 0
  if classID == nil then return false end -- noch nicht bekannt: nicht cachen
  if classID ~= consumable then
    itemKind[itemID] = false
    return false
  end
  -- Ohne Item-Zauber (oder solange die Daten noch laden) nicht dauerhaft
  -- als "kein Buff-Item" merken: frisch geplünderte oder beim Einloggen
  -- noch nicht geladene Items würden sonst bis /reload fehlen.
  local spellName = safe(C_Item.GetItemSpell, itemID)
  if not spellName then
    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    return false
  end
  local lines = tooltipLines(bag, slot)
  local complete = false
  for _, line in ipairs(lines) do
    if line:find("benutzen") or line:find("use:") then complete = true break end
  end
  if not complete then return false end -- Tooltip noch unvollständig: nicht cachen

  local kind = false
  for _, line in ipairs(lines) do
    for _, p in ipairs(FOOD_PATTERNS) do
      if line:find(p, 1, true) then kind = "food" break end
    end
    if kind then break end
  end
  if not kind then
    for _, line in ipairs(lines) do
      if (line:find("benutzen") or line:find("use:")) and longDuration(line) then
        kind = "buff" break
      end
    end
  end
  itemKind[itemID] = kind
  return kind
end

local function scanBags()
  local foods, buffs = {}, {}
  local seen = {}
  local lastBag = (NUM_BAG_SLOTS or 4)
  for bag = 0, lastBag do
    local slots = safe(C_Container.GetContainerNumSlots, bag) or 0
    for slot = 1, slots do
      local id = safe(C_Container.GetContainerItemID, bag, slot)
      if id and not seen[id] then
        seen[id] = true
        if not BuffCheckDB.ignored[id] then
          local kind = classify(id, bag, slot)
          if kind == "food" then
            table.insert(foods, id)
          elseif kind == "buff" then
            buffs[id] = true
          end
        end
      end
    end
  end
  -- Manuell hinzugefügte Items immer mitprüfen
  for id in pairs(BuffCheckDB.items) do
    if not BuffCheckDB.ignored[id] and (safe(C_Item.GetItemCount, id) or 0) > 0 then
      buffs[id] = true
    end
  end
  return foods, buffs
end

-- Item benutzbar (Mindeststufe)? Unbekannt (noch nicht geladen) = ja
local function levelOK(id)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local name, _, _, _, minLevel = safe(getInfo, id)
  if not name then
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return true
  end
  return not minLevel or minLevel <= UnitLevel("player")
end

local function inBags(id)
  return not BuffCheckDB.ignored[id] and (safe(C_Item.GetItemCount, id) or 0) > 0
end


-- Für die anderen Module
ns.WELL_FED = WELL_FED
ns.itemKind = itemKind
ns.tooltipLines = tooltipLines
ns.longDuration = longDuration
ns.classify = classify
ns.scanBags = scanBags
ns.levelOK = levelOK
ns.inBags = inBags
