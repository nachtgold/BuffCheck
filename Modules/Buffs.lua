-- BuffCheck – Prüfung: Klassenbuffs, Waffen, Essen, Buff-Items

local ADDON, ns = ...
local L = ns.L

local CAMP_ITEM, CLASS, WELL_FED, campBlockedSpells = ns.CAMP_ITEM, ns.CLASS, ns.WELL_FED, ns.campBlockedSpells
local collectAlchemy, collectCamp, hasAnyBuff, hasBuff = ns.collectAlchemy, ns.collectCamp, ns.hasAnyBuff, ns.hasBuff
local isSecret, knownSpell, levelOK, professionSkills = ns.isSecret, ns.knownSpell, ns.levelOK, ns.professionSkills
local roleKey, safe, scanBags, warnBefore = ns.roleKey, ns.safe, ns.scanBags, ns.warnBefore

------------------------------------------------------------------------
-- Klassen-Gruppen kommen aus Classes\<Klasse>.lua: nur die Datei der eigenen
-- Klasse läuft und legt ns.CLASS an. Ein Eintrag fehlt, wenn KEINER der Buffs
-- aktiv ist und du mindestens einen der Zauber kennst. Vorgeschlagen wird der
-- zuletzt aktive Zauber der Gruppe, sonst der erste bekannte.
--   spells = Buffs, die die Gruppe erfüllen
--   cast   = (optional) nur diese Zauber vorschlagen
--   prof   = (optional) Zauber -> nötiger Beruf
--   weapon = Waffenverzauberung statt Buff: { slots, spells oder items, labels }
------------------------------------------------------------------------
local GROUPS = {}
for _, g in ipairs(CLASS.groups) do table.insert(GROUPS, g) end
for _, g in ipairs({
  {
    -- Sammelberufe: nur eine Suche kann aktiv sein; nur mit dem passenden Beruf
    key = "suche", label = L["Suche (Sammelberuf)"],
    spells = { "Kräutersuche", "Find Herbs", "Mineraliensuche", "Find Minerals" },
    prof = {
      ["Kräutersuche"] = { "kräuterkunde", "herbalism" },
      ["Find Herbs"] = { "kräuterkunde", "herbalism" },
      ["Mineraliensuche"] = { "bergbau", "mining" },
      ["Find Minerals"] = { "bergbau", "mining" },
    },
  },
}) do table.insert(GROUPS, g) end


------------------------------------------------------------------------
-- Prüfung
------------------------------------------------------------------------
local function itemEntry(id, label)
  return {
    text = label or safe(C_Item.GetItemNameByID, id) or ("Item " .. id),
    icon = safe(C_Item.GetItemIconByID, id),
    type = "item", value = "item:" .. id, itemID = id,
  }
end

------------------------------------------------------------------------
-- Zuletzt benutzter Zauber je Gruppe (pro Charakter): wird als nächstes
-- vorgeschlagen, z. B. deine gewohnte Aura oder Rüstung.
------------------------------------------------------------------------
local function lastSpells()
  BuffCheckDB.last = BuffCheckDB.last or {}
  local k = roleKey()
  BuffCheckDB.last[k] = BuffCheckDB.last[k] or {}
  return BuffCheckDB.last[k]
end

-- Waffen-Zauber (Schamane): gewirkte Verzauberung merken
local WEAPON_SPELL = {}
for _, g in ipairs(GROUPS) do
  if g.weapon and g.weapon.spells then
    for _, n in ipairs(g.weapon.spells) do WEAPON_SPELL[n:lower()] = g.key end
  end
end
if next(WEAPON_SPELL) then
  local castWatch = CreateFrame("Frame")
  pcall(castWatch.RegisterUnitEvent, castWatch, "UNIT_SPELLCAST_SUCCEEDED", "player")
  castWatch:SetScript("OnEvent", function(_, _, _, _, spellID)
    local name = spellID and safe(C_Spell.GetSpellName, spellID)
    local key = name and WEAPON_SPELL[name:lower()]
    if key then lastSpells()[key] = name end
  end)
end

-- Waffenverzauberung: Restzeit je Slot (16 Waffenhand, 17 Schildhand)
local function weaponEnchant(slot)
  if not GetWeaponEnchantInfo then return nil end
  local ok, hasMH, mhExp, _, _, hasOH, ohExp = pcall(GetWeaponEnchantInfo)
  if not ok or isSecret(hasMH) or isSecret(hasOH) then return nil end
  local has, exp = hasMH, mhExp
  if slot == 17 then has, exp = hasOH, ohExp end
  if not has then return false end
  if type(exp) == "number" and not isSecret(exp) then
    local rem = exp / 1000
    if rem < warnBefore() then return false, rem end
  end
  return true
end

-- Liegt in diesem Slot eine Waffe? (Schildhand: kein Schild/Buch)
local function hasWeapon(slot)
  local id = GetInventoryItemID and GetInventoryItemID("player", slot)
  if not id or isSecret(id) then return false end
  if slot == 16 then return true end
  local getInfo = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local _, _, _, _, _, classID = safe(getInfo, id)
  return classID == 2
end

-- Bestes Gift für einen Slot aus der Tasche (Namensmuster, höchster Rang)
local WEAPON_ITEM = {} -- erkannte Gifte: nicht zusätzlich als Buff-Item zeigen
local function findWeaponItem(prefs)
  local found = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (safe(C_Container.GetContainerNumSlots, bag) or 0) do
      local id = safe(C_Container.GetContainerItemID, bag, slot)
      local name = id and safe(C_Item.GetItemNameByID, id)
      if name then
        name = name:lower()
        for p, pats in ipairs(prefs) do
          for _, pat in ipairs(pats) do
            if name:find(pat, 1, true) then
              WEAPON_ITEM[id] = true
              if not BuffCheckDB.ignored[id] and levelOK(id) and (not found[p] or id > found[p]) then
                found[p] = id
              end
            end
          end
        end
      end
    end
  end
  for p = 1, #prefs do if found[p] then return found[p] end end
end

local function collectWeapon(g, missing)
  local w = g.weapon
  for _, slot in ipairs(w.slots) do
    local state, rem = weaponEnchant(slot)
    if state == false and hasWeapon(slot) then
      local label = (w.labels and w.labels[slot]) or g.label
      if w.spells then
        local last = lastSpells()[g.key]
        local info = last and knownSpell(last)
        if not info then
          for _, n in ipairs(w.spells) do
            info = knownSpell(n)
            if info then break end
          end
        end
        if info then
          table.insert(missing, { text = label, icon = info.iconID, hint = info.name,
            type = "spell", value = info.name, expiring = rem })
        end
      elseif w.items then
        local id = findWeaponItem(w.items[slot])
        if id then
          local e = itemEntry(id, label)
          e.type, e.value = "macro", ("/use item:%d\n/use %d"):format(id, slot)
          e.hint = safe(C_Item.GetItemNameByID, id)
          e.expiring = rem
          table.insert(missing, e)
        end
      end
    end
  end
end

local function collectMissing()
  local missing = {}

  -- Klassenbuffs (ohne die, die ein aktiver Lager-Buff blockiert)
  local campBlocked = campBlockedSpells()
  local profs -- erst bei Bedarf ermitteln
  local function hasProf(names)
    profs = profs or professionSkills()
    for _, n in ipairs(names) do if profs[n] then return true end end
    return false
  end
  local last = lastSpells()
  for _, g in ipairs(GROUPS) do
    if BuffCheckDB.enabled[g.key] and g.weapon then
      collectWeapon(g, missing)
    elseif BuffCheckDB.enabled[g.key] then
      local castInfo, unreadable, active, expiring = nil, false, false, nil
      local function usable(name)
        -- Zauber, die einen Beruf brauchen, nur vorschlagen, wenn du ihn hast
        if g.cast and not g.cast[name] then return false end
        if g.prof and g.prof[name] and not hasProf(g.prof[name]) then return false end
        return not campBlocked[name:lower()]
      end
      for _, name in ipairs(g.spells) do
        local state, rem = hasBuff(name)
        if state == nil then unreadable = true end
        if state then
          active = true
          if usable(name) then last[g.key] = name end
          break
        end
        if usable(name) then
          if rem then
            -- Läuft ab: genau diesen Buff erneuern, wenn du ihn kennst
            expiring = math.max(expiring or 0, rem)
            castInfo = knownSpell(name) or castInfo
          end
          if not castInfo then castInfo = knownSpell(name) end
        end
      end
      -- Sonst den zuletzt aktiven Zauber der Gruppe vorschlagen
      if not expiring and last[g.key] and usable(last[g.key]) then
        castInfo = knownSpell(last[g.key]) or castInfo
      end
      if not active and not unreadable and castInfo then
        table.insert(missing, {
          text = g.label, icon = castInfo.iconID,
          type = "spell", value = castInfo.name, expiring = expiring,
        })
      end
    end
  end

  -- Alchemie: selbst herstellbare Buffs gelten als gebraucht
  local handled = {}
  if BuffCheckDB.enabled.alchemie then handled = collectAlchemy(missing) end

  if BuffCheckDB.enabled.lager then collectCamp(missing) end

  local foods, buffs = scanBags()

  -- Buff-Essen: ein Icon, wenn "Satt" fehlt und Buff-Essen in der Tasche ist
  if BuffCheckDB.enabled.essen and #foods > 0 then
    local fed, rem = hasAnyBuff(WELL_FED)
    if fed == false then
      local preferred = BuffCheckDB.food
      local pick = foods[1]
      for _, id in ipairs(foods) do if id == preferred then pick = id end end
      local e = itemEntry(pick, L["Essen"])
      e.expiring = rem
      table.insert(missing, e)
    end
  end

  -- Elixiere, Fläschchen, Rollen usw.
  if BuffCheckDB.enabled.elixier then
    local sorted = {}
    for id in pairs(buffs) do table.insert(sorted, id) end
    table.sort(sorted)
    local seenBuff = {}
    for _, id in ipairs(sorted) do
      local buff = safe(C_Item.GetItemSpell, id)
      if buff and not seenBuff[buff] and not handled[id] and not CAMP_ITEM[id] and not WEAPON_ITEM[id] then
        seenBuff[buff] = true -- gleiche Wirkung (z. B. zwei Ränge) nur einmal zeigen
        local s, rem = hasBuff(buff)
        if s == false then
          local e = itemEntry(id)
          e.expiring = rem
          table.insert(missing, e)
        end
      end
    end
  end

  return missing
end

-- Für die anderen Module
ns.GROUPS = GROUPS
ns.itemEntry = itemEntry
ns.lastSpells = lastSpells
ns.WEAPON_SPELL = WEAPON_SPELL
ns.weaponEnchant = weaponEnchant
ns.hasWeapon = hasWeapon
ns.WEAPON_ITEM = WEAPON_ITEM
ns.findWeaponItem = findWeaponItem
ns.collectWeapon = collectWeapon
ns.collectMissing = collectMissing
