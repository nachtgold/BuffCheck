-- BuffCheck – zeigt fehlende Selbst-Buffs für WoW Forever (Interface 16001)
-- Klassenbuffs, Buff-Essen sowie Elixiere/Fläschchen/Rollen aus den Taschen.
-- Prüft nur außerhalb des Kampfs (im Kampf sind Aura-Daten für Addons gesperrt).
-- Linksklick auf ein Icon: wirken/benutzen. Rechtsklick: Item ignorieren.

local ADDON, ns = ...
local L = ns.L
local ICON_SIZE = 40
local REFRESH_BELOW = 30      -- Sekunden Restlaufzeit, ab der ein Buff als "fehlt" gilt
local MIN_BUFF_MINUTES = 10   -- Verbrauchsgüter mit kürzerer Wirkung (Heiltränke etc.) ignorieren

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
local CLASS = ns.CLASS or { groups = {}, roleByTab = {}, roles = { "dd" }, defaultRole = "dd" }
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

-- Name des Essens-Buffs (deutsch / englisch)
local WELL_FED = { "Satt", "Well Fed" }
-- Textstellen im Tooltip, an denen Buff-Essen erkannt wird
local FOOD_PATTERNS = { "satt", "well fed" }

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
-- Lagerfeuer (Camping): Am Feuer stellt jeder Spieler EIN Lagerobjekt seines
-- Berufs dazu (alle Objekte teilen 1 Std. Abklingzeit). Nach einer Minute am
-- Feuer gibt es die Stärkungen aller Objekte als einen Buff. Daten:
-- wowhead.com/forever (Stand 06.11.2026). items: bestes zuerst (Stufe 3, 2, 1),
-- Stufe 2/3 geben dieselbe Stärkung wie Stufe 1 plus Extras.
-- labels: Objektnamen, wie sie im Tooltip des Lager-Buffs stehen (Stufe 1).
-- conflicts: Klassenbuffs, mit denen die Stärkung nicht zusammen wirkt.
------------------------------------------------------------------------
local CAMP_OBJECTS = {
  alchimie = { labels = { "Manabrunnen", "Mana Well" }, names = { "alchemie", "alchemy" }, effect = L["Mana alle 5 Sek."],
    items = { 279990, 279970, 279956 },
    conflicts = { "Segen der Weisheit", "Großer Segen der Weisheit", "Blessing of Wisdom", "Greater Blessing of Wisdom" } },
  schmiede = { labels = { "Schleifstein", "Sharpening Wheel" }, names = { "schmiedekunst", "blacksmithing" }, effect = L["Stärke"],
    items = { 279955, 279988, 279944 },
    conflicts = { "Stärke der Erde", "Strength of Earth" } },
  verzauber = { labels = { "Verzauberte Laute", "Enchanted Lute" }, names = { "verzauberkunst", "enchanting" }, effect = L["Rüstung und alle Werte"],
    items = { 279987, 279985, 279976 },
    conflicts = { "Mal der Wildnis", "Gabe der Wildnis", "Mark of the Wild", "Gift of the Wild" } },
  ingenieur = { names = { "ingenieurskunst", "engineering" }, effect = L["Reagenzien und Reparatur (kein Buff)"],
    items = { 279989, 279949, 279950 }, noBuff = true },
  kraeuter = { labels = { "Räucherkerze", "Incense Candle" }, names = { "kräuterkunde", "herbalism" }, effect = L["Intelligenz"],
    items = { 279947, 279964, 279962 },
    conflicts = { "Arkane Intelligenz", "Arkane Brillanz", "Arcane Intellect", "Arcane Brilliance" } },
  leder = { names = { "lederverarbeitung", "leatherworking" }, effect = L["Ruhebonus (Erfahrung)"],
    items = { 279945, 279941, 279978 } },
  bergbau = { labels = { "Leitstein", "Lodestone" }, names = { "bergbau", "mining" }, effect = L["Angriffskraft"],
    items = { 279952, 279948, 279960 },
    conflicts = { "Segen der Macht", "Großer Segen der Macht", "Blessing of Might", "Greater Blessing of Might" } },
  kuerschner = { labels = { "Lagerstuhl", "Camp Chair" }, names = { "kürschnerei", "skinning" }, effect = L["2 % kritische Trefferchance"],
    items = { 279938, 279969, 279979 },
    conflicts = { "Aura des Moonkin", "Moonkin-Aura", "Moonkin Aura" } },
  schneider = { labels = { "Fraktionsbanner", "Faction Banner" }, names = { "schneiderei", "tailoring" }, effect = L["Willenskraft"],
    items = { 279959, 279943, 279972 },
    conflicts = { "Göttlicher Willen", "Gebet der Willenskraft", "Divine Spirit", "Prayer of Spirit" } },
  erstehilfe = { labels = { "Verbandtasche", "First Aid Kit" }, names = { "erste hilfe", "first aid" }, effect = L["Ausdauer"],
    items = { 279951, 279940, 279968 },
    conflicts = { "Machtwort: Seelenstärke", "Gebet der Seelenstärke", "Power Word: Fortitude", "Prayer of Fortitude" } },
  angeln = { labels = { "Fischglas", "Fish Bowl" }, names = { "angeln", "fishing" }, effect = L["8 % auf alle Werte"],
    items = { 279966, 279965, 279967 },
    conflicts = { "Segen der Könige", "Großer Segen der Könige", "Blessing of Kings", "Greater Blessing of Kings" } },
}
local CAMP_TIER1_SKILL = 20

-- Reihenfolge: welches Objekt der Gruppe am meisten bringt
local CAMP_PRIORITY = {
  heal = { "alchimie", "kraeuter", "angeln", "verzauber", "schneider", "erstehilfe",
           "leder", "kuerschner", "bergbau", "schmiede", "ingenieur" },
  tank = { "erstehilfe", "angeln", "verzauber", "schmiede", "bergbau", "kuerschner",
           "leder", "alchimie", "kraeuter", "schneider", "ingenieur" },
  dd   = { "bergbau", "kuerschner", "angeln", "schmiede", "verzauber", "erstehilfe",
           "leder", "alchimie", "kraeuter", "schneider", "ingenieur" },
  caster = { "kraeuter", "alchimie", "kuerschner", "angeln", "verzauber", "schneider",
           "erstehilfe", "leder", "bergbau", "schmiede", "ingenieur" },
}

-- Lagerfeuer-Sets (werden nicht als Buff-Item behandelt)
local CAMP_KITS = { 279981, 279961, 279974 }
local CAMP_ITEM = {}
for _, o in pairs(CAMP_OBJECTS) do for _, id in ipairs(o.items) do CAMP_ITEM[id] = true end end
for _, id in ipairs(CAMP_KITS) do CAMP_ITEM[id] = true end

-- Woran ein Lagerfeuer in der Nähe erkannt wird
local CAMP_AURA_PATTERNS = { "lagerfeuer", "campfire", "lager", "camp" }
local CAMP_SPELL_PATTERNS = { "lagerfeuer", "campfire" }
local CAMP_RANGE = 15         -- Meter um ein beobachtetes Feuer
local CAMP_FIRE_LIFETIME = 1800 -- so lange gilt ein beobachtetes Feuer als vorhanden

------------------------------------------------------------------------
-- Hilfsfunktionen (alles defensiv: geheime Werte & fehlende APIs abfangen)
------------------------------------------------------------------------
local function isSecret(v)
  return issecretvalue and issecretvalue(v) or false
end

local function safe(fn, ...)
  if not fn then return nil end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if not ok or isSecret(a) then return nil end
  return a, b, c, d, e, f, g
end

local function knownSpell(name)
  return safe(C_Spell.GetSpellInfo, name)
end

-- Ab wie vielen Sekunden Restzeit ein Buff als "läuft ab" gilt (einstellbar)
local function warnBefore()
  return (BuffCheckDB and BuffCheckDB.warnBefore) or REFRESH_BELOW
end

-- Restzeit einer Aura in Sekunden, nil = unbegrenzt/unbekannt
local function auraRemaining(aura)
  local exp = aura.expirationTime
  if type(exp) ~= "number" or isSecret(exp) or exp <= 0 then return nil end
  return exp - GetTime()
end

-- Prüft eine Aura: true = aktiv, false (+ Restzeit) = fehlt bzw. läuft ab
local function judge(aura)
  local rem = auraRemaining(aura)
  if rem and rem < warnBefore() then return false, rem end
  return true, rem
end

-- true = aktiv, false = fehlt (2. Wert: Restzeit, wenn er gerade abläuft),
-- nil = nicht lesbar (dann nichts anzeigen)
local function hasBuff(name)
  local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
  if not ok then return nil end
  if not aura then return false end
  if isSecret(aura) then return nil end
  return judge(aura)
end

-- Buff per Spell-ID prüfen, Rückfall auf den (lokalisierten) Namen
local function hasSpellBuff(spellID, itemID)
  if spellID and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if ok and aura and not isSecret(aura) then
      return judge(aura)
    end
  end
  local name = (spellID and safe(C_Spell.GetSpellName, spellID))
    or (itemID and safe(C_Item.GetItemSpell, itemID))
  if not name then return false end
  return hasBuff(name)
end

local function hasAnyBuff(names)
  local unreadable, expiring = false, nil
  for _, n in ipairs(names) do
    local s, rem = hasBuff(n)
    if s then return true end
    if s == nil then unreadable = true end
    if rem then expiring = math.max(expiring or 0, rem) end
  end
  if unreadable then return nil end
  return false, expiring
end

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

------------------------------------------------------------------------
-- Alchemie-Skill und Rolle
------------------------------------------------------------------------
local function alchemySkill()
  if GetProfessions and GetProfessionInfo then
    local profs = { pcall(GetProfessions) }
    if profs[1] then
      for i = 2, 3 do
        local idx = profs[i]
        if idx and not isSecret(idx) then
          local name, _, rank, _, _, _, skillLine = safe(GetProfessionInfo, idx)
          if rank and (skillLine == ALCHEMY_SKILLLINE or (name and ALCHEMY_NAMES[name:lower()])) then
            return rank
          end
        end
      end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, (safe(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank = safe(GetSkillLineInfo, i)
      if name and not isHeader and ALCHEMY_NAMES[name:lower()] then return rank or 0 end
    end
  end
  return 0
end

local ROLE_BY_TAB = CLASS.roleByTab -- Talentbaum -> Rolle

-- Rollen, die für die Klasse in Frage kommen (plus "alle" und "auto")
local CLASS_ROLE = { alle = true, auto = true }
for _, r in ipairs(CLASS.roles) do CLASS_ROLE[r] = true end

-- Rolle pro Charakter (früher kontoweit in BuffCheckDB.role)
local function roleKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end
local function getRole()
  local r = BuffCheckDB.roles and BuffCheckDB.roles[roleKey()]
  if r and CLASS_ROLE[r] then return r end
  r = BuffCheckDB.role
  if r and CLASS_ROLE[r] then return r end
  return "alle"
end
local function setRole(r)
  BuffCheckDB.roles = BuffCheckDB.roles or {}
  BuffCheckDB.roles[roleKey()] = r
end

local function currentRole(forceAuto)
  local r = getRole()
  if not forceAuto and r ~= "auto" and ROLE_SLOTS[r] then return r end
  local fallback = CLASS.defaultRole or "dd"
  if GetSpecialization then
    local s = safe(GetSpecialization)
    if s and ROLE_BY_TAB[s] then return ROLE_BY_TAB[s] end
  end
  if GetNumTalentTabs and GetTalentTabInfo then
    local best, bestPts = nil, 0
    for i = 1, (safe(GetNumTalentTabs) or 0) do
      local res = { pcall(GetTalentTabInfo, i) }
      if res[1] then
        -- Classic: name, icon, punkte  |  neuere API: id, name, beschr., icon, punkte
        local pts = type(res[4]) == "number" and res[4] or (type(res[6]) == "number" and res[6]) or 0
        if not isSecret(pts) and pts > bestPts then best, bestPts = i, pts end
      end
    end
    if best and ROLE_BY_TAB[best] then return ROLE_BY_TAB[best] end
  end
  return fallback
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
  local found, reagents, any = {}, {}, false
  local T = C_TradeSkillUI
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
  return any
end

-- Zutatenliste eines Tranks (gemerkt oder live aus der Rezeptdatenbank)
local function reagentsFor(itemID)
  local list = BuffCheckDB.reagents and BuffCheckDB.reagents[itemID]
  if list then return list end
  local rid = (knownRecipes() or {})[itemID]
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

local function alchemyWindowOpen()
  local T = C_TradeSkillUI
  if T and T.IsTradeSkillReady and not safe(T.IsTradeSkillReady) then return false end
  if T and T.GetBaseProfessionInfo then
    local info = safe(T.GetBaseProfessionInfo)
    if info and info.professionID == ALCHEMY_SKILLLINE then return true end
  end
  if T and T.GetTradeSkillLine then
    if safe(T.GetTradeSkillLine) == ALCHEMY_SKILLLINE then return true end
  end
  if GetTradeSkillLine then
    local name = safe(GetTradeSkillLine)
    if type(name) == "string" and ALCHEMY_NAMES[name:lower()] then return true end
  end
  return false
end

-- true = Herstellen gestartet (oder sinnvoll abgebrochen), false = ging nicht
local function doCraft(itemID)
  local name = safe(C_Item.GetItemNameByID, itemID) or ("Item " .. itemID)
  local T = C_TradeSkillUI
  local known = knownRecipes() or {}
  local rid = type(known[itemID]) == "number" and known[itemID] or nil
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
local function craftItem(itemID)
  if InCombatLockdown() then return end
  if alchemyWindowOpen() and doCraft(itemID) then
    craftCast.closeWindow = true -- nach dem Herstellen Fenster wieder schließen
    return
  end
  local T = C_TradeSkillUI
  local rid = (knownRecipes() or {})[itemID]
  -- Fenster gleich beim richtigen Rezept öffnen, sonst nur das Fenster
  local opened = (T and T.OpenRecipe and type(rid) == "number" and pcall(T.OpenRecipe, rid))
    or (T and T.OpenTradeSkill and pcall(T.OpenTradeSkill, ALCHEMY_SKILLLINE))
  if not opened then
    chat(L["Bitte das Alchemie-Fenster öffnen und dann nochmal auf das Icon klicken."])
    return
  end
  -- Sind die Rezeptdaten sofort da, gleich im selben Klick herstellen
  if alchemyWindowOpen() and doCraft(itemID) then
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
  local skill = alchemySkill()
  if skill <= 0 and not knownRecipes() then return handled end
  local role = currentRole()
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
local function openRecipe(itemID)
  if InCombatLockdown() then return end
  local T = C_TradeSkillUI
  local rid = (knownRecipes() or {})[itemID]
  if T and T.OpenRecipe and type(rid) == "number" and pcall(T.OpenRecipe, rid) then return end
  if T and T.OpenTradeSkill and pcall(T.OpenTradeSkill, ALCHEMY_SKILLLINE) then
    -- alte Fenster: Rezept auswählen, sobald die Liste da ist
    local idx = tradeIndexOf[itemID]
    if idx and SelectTradeSkill then C_Timer.After(0.2, function() pcall(SelectTradeSkill, idx) end) end
    return
  end
  chat(L["Bitte das Alchemie-Fenster öffnen und dann nochmal auf das Icon klicken."])
end

------------------------------------------------------------------------
-- Lagerfeuer
------------------------------------------------------------------------
-- Alle Berufe (auch Nebenberufe) mit Skill: kleingeschriebener Name -> Rang
local function professionSkills()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local profs = { pcall(GetProfessions) }
    if profs[1] then
      for i = 2, 7 do
        local idx = profs[i]
        if idx and not isSecret(idx) then
          local name, _, rank = safe(GetProfessionInfo, idx)
          if name and rank then out[name:lower()] = rank end
        end
      end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, (safe(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank = safe(GetSkillLineInfo, i)
      if name and not isHeader and rank then out[name:lower()] = rank end
    end
  end
  return out
end

local function campSkill(obj, skills)
  for _, n in ipairs(obj.names) do
    if skills[n] then return skills[n] end
  end
  return 0
end

-- Beobachtete Lagerfeuer (eigene oder von Gruppenmitgliedern aufgestellt)
local campFires = {}

local function unitPos(unit)
  if not UnitPosition then return nil end
  local y, x, _, inst = safe(UnitPosition, unit)
  if type(x) ~= "number" or type(y) ~= "number" then return nil end
  return x, y, inst
end

local function matchesAny(text, patterns)
  if not text or isSecret(text) then return false end
  text = text:lower()
  for _, p in ipairs(patterns) do
    if text:find(p, 1, true) then return true end
  end
  return false
end

local fireWatch = CreateFrame("Frame")
pcall(fireWatch.RegisterEvent, fireWatch, "UNIT_SPELLCAST_SUCCEEDED")
fireWatch:SetScript("OnEvent", function(_, _, unit, _, spellID)
  if isSecret(spellID) or isSecret(unit) then return end
  local name = spellID and safe(C_Spell.GetSpellName, spellID)
  if not matchesAny(name, CAMP_SPELL_PATTERNS) then return end
  local x, y, inst = unitPos(unit)
  if not x then return end
  table.insert(campFires, { x = x, y = y, inst = inst, t = GetTime() })
  if ns.queueUpdate then ns.queueUpdate() end
end)

-- Aura am Spieler, die nach Lagerfeuer aussieht (frisch oder ohne Laufzeit)
local function campAura()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  for i = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok or not aura then break end
    if not isSecret(aura) and matchesAny(aura.name, CAMP_AURA_PATTERNS) then
      local dur, exp = aura.duration, aura.expirationTime
      if isSecret(dur) or isSecret(exp) then return aura.name end
      -- Ohne Laufzeit = Gebiets-Aura des Feuers; sonst nur in den ersten 2 Min.
      -- (der fertige Lager-Buff hält 1 Std. und wirkt auch fern vom Feuer)
      if not dur or dur == 0 or (exp - dur) > GetTime() - 120 then return aura.name end
    end
  end
  return nil
end

-- Bist du an einem Lagerfeuer? Liefert eine Begründung (für /bc lager)
local function nearCampfire()
  local aura = campAura()
  if aura then return true, L["Buff: %s"]:format(aura) end
  local x, y, inst = unitPos("player")
  local now = GetTime()
  for i = #campFires, 1, -1 do
    local f = campFires[i]
    if now - f.t > CAMP_FIRE_LIFETIME then
      table.remove(campFires, i)
    elseif x and f.inst == inst then
      local d = math.sqrt((x - f.x) ^ 2 + (y - f.y) ^ 2)
      if d <= CAMP_RANGE then return true, L["Feuer in %d m"]:format(d) end
    end
  end
  return false
end

local function campRole()
  local role = currentRole()
  if CAMP_PRIORITY[role] then return role end
  -- "alle": Rolle nach Talentbaum
  role = currentRole(true)
  return CAMP_PRIORITY[role] and role or "dd"
end

-- Ist die gemeinsame Abklingzeit der Lagerobjekte aktiv (schon eins aufgestellt)?
local function campOnCooldown(id)
  local getCD = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  local start, dur = safe(getCD, id)
  return type(start) == "number" and type(dur) == "number" and start > 0 and dur > 2
end

local campBuff -- weiter unten definiert

-- Steht dieses Objekt schon im Lager? (Name im Tooltip des Lager-Buffs)
local function campObjectInText(obj, text)
  if not text or text == "" then return false end
  local names = {}
  for _, n in ipairs(obj.labels or {}) do table.insert(names, n) end
  for _, id in ipairs(obj.items) do
    local n = safe(C_Item.GetItemNameByID, id)
    if n then table.insert(names, n) end
  end
  for _, n in ipairs(names) do
    if text:find(n:lower(), 1, true) then return true end
  end
  return false
end

-- Bewertet jedes Lagerobjekt, das du aufstellen oder herstellen könntest
local function campCandidates()
  local _, campText = campBuff()
  local skills = professionSkills()
  local level = UnitLevel("player")
  local maxLevel = (GetMaxPlayerLevel and safe(GetMaxPlayerLevel)) or 60
  local order = CAMP_PRIORITY[campRole()]
  if level < maxLevel then
    -- Beim Leveln bringt das Lagerzelt (Ruhebonus) am meisten
    local o = { "leder" }
    for _, k in ipairs(order) do if k ~= "leder" then table.insert(o, k) end end
    order = o
  end
  local list = {}
  for _, key in ipairs(order) do
    local obj = CAMP_OBJECTS[key]
    local have
    for _, id in ipairs(obj.items) do
      if inBags(id) then have = id break end
    end
    local skill = campSkill(obj, skills)
    if have or skill >= CAMP_TIER1_SKILL then
      local blockedBy
      for _, n in ipairs(obj.conflicts or {}) do
        if hasBuff(n) then blockedBy = n break end
      end
      table.insert(list, { key = key, obj = obj, have = have, skill = skill, blockedBy = blockedBy,
        inCamp = campObjectInText(obj, campText) })
    end
  end
  return list
end

local function campItemName(id)
  return safe(C_Item.GetItemNameByID, id) or ("Item " .. id)
end

local function collectCamp(missing)
  if not nearCampfire() then return end
  local list = campCandidates()
  if #list == 0 then return end
  -- Schon ein Objekt aufgestellt? Dann ist die gemeinsame Abklingzeit aktiv.
  for _, c in ipairs(list) do
    if campOnCooldown(c.have or c.obj.items[#c.obj.items]) then return end
  end
  -- Bestes Objekt: noch nicht im Lager, vorrätig und nicht durch einen
  -- Klassenbuff wirkungslos
  local pick
  for _, c in ipairs(list) do
    if c.have and not c.blockedBy and not c.inCamp then pick = c break end
  end
  for _, c in ipairs(list) do
    if not pick and not c.blockedBy and not c.inCamp then pick = c end
  end
  -- Alles Sinnvolle steht schon im Lager: nichts vorschlagen
  if not pick then return end

  local extra = {}
  table.insert(extra, { L["Bringt: %s"]:format(pick.obj.effect), 1, 1, 1 })
  if pick.blockedBy then
    table.insert(extra, { L["Wirkt nicht zusammen mit %s (aktiv)"]:format(pick.blockedBy), 1, 0.25, 0.25 })
  end
  if #list > 1 then
    table.insert(extra, { " " })
    table.insert(extra, { L["Weitere Möglichkeiten:"] })
    for _, c in ipairs(list) do
      if c ~= pick then
        local id = c.have or c.obj.items[#c.obj.items]
        local state = (c.inCamp and L["steht schon im Lager"])
          or (c.blockedBy and L["wirkt nicht mit %s"]:format(c.blockedBy))
          or (c.have and L["in der Tasche"]) or L["herstellen"]
        table.insert(extra, { ("  %s – %s (%s)"):format(campItemName(id), c.obj.effect, state), 0.8, 0.8, 0.8 })
      end
    end
  end
  table.insert(extra, { " " })
  table.insert(extra, { L["Jedes Objekt gibt es nur einmal pro Lager. Steht deins schon, nimm das nächste."], 0.7, 0.7, 0.7 })

  if pick.have then
    table.insert(missing, {
      text = L["Lager"], icon = safe(C_Item.GetItemIconByID, pick.have),
      type = "item", value = "item:" .. pick.have, itemID = pick.have,
      hint = L["Am Lagerfeuer aufstellen: %s"]:format(campItemName(pick.have)), extra = extra,
    })
  else
    local id = pick.obj.items[#pick.obj.items] -- Stufe 1, gleiche Stärkung
    table.insert(missing, {
      text = L["Lager"], icon = safe(C_Item.GetItemIconByID, id), info = true,
      hint = L["Herstellen und aufstellen: %s (nicht in der Tasche)"]:format(campItemName(id)), extra = extra,
    })
  end
end

-- Verstecktes Tooltip zum Auslesen von Buff-Texten (klassischer Weg, falls
-- C_TooltipInfo für Auren nichts liefert)
local scanTip
local function scanBuffTooltip(index)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "BuffCheckScanTooltip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  local ok = (scanTip.SetUnitBuff and pcall(scanTip.SetUnitBuff, scanTip, "player", index))
    or (scanTip.SetUnitAura and pcall(scanTip.SetUnitAura, scanTip, "player", index, "HELPFUL"))
  local out = {}
  if ok then
    for n = 1, (scanTip:NumLines() or 0) do
      for _, side in ipairs({ "Left", "Right" }) do
        local fs = _G["BuffCheckScanTooltipText" .. side .. n]
        local t = fs and fs:GetText()
        if type(t) == "string" and not isSecret(t) then table.insert(out, t:lower()) end
      end
    end
  end
  scanTip:Hide()
  return out
end

-- Aktiver Lager-Buff (Camp Benefits) und der Text seines Tooltips (klein)
function campBuff()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
  for i = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok or not aura then break end
    if not isSecret(aura) and matchesAny(aura.name, CAMP_AURA_PATTERNS) then
      local text = {}
      local T = C_TooltipInfo
      local data = T and ((aura.auraInstanceID and T.GetUnitBuffByAuraInstanceID
          and safe(T.GetUnitBuffByAuraInstanceID, "player", aura.auraInstanceID))
        or (T.GetUnitAura and safe(T.GetUnitAura, "player", i, "HELPFUL"))
        or (T.GetUnitBuff and safe(T.GetUnitBuff, "player", i)))
      if data and TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, data)
        for _, l in ipairs(data.lines or {}) do pcall(TooltipUtil.SurfaceArgs, l) end
      end
      for _, l in ipairs(data and data.lines or {}) do
        for _, t in ipairs({ l.leftText, l.rightText }) do
          if type(t) == "string" and not isSecret(t) then table.insert(text, t:lower()) end
        end
      end
      if #text == 0 then text = scanBuffTooltip(i) end
      local desc = aura.spellId and not isSecret(aura.spellId)
        and safe(C_Spell.GetSpellDescription, aura.spellId)
      if type(desc) == "string" then table.insert(text, desc:lower()) end
      return aura, table.concat(text, "\n")
    end
  end
  return nil
end

-- Aus Fehlermeldungen gelernt: Zauber, die der Lager-Buff blockiert
-- ("Ein mächtigerer Zauber ist bereits aktiv"). Name (klein) -> Ablaufzeit
local learnedBlocked = {}

-- Klassenbuffs, die der aktive Lager-Buff blockiert: Objektnamen im Tooltip
-- des Lager-Buffs suchen, dazu die gelernten. Menge: Zaubername (klein) -> true
local function campBlockedSpells()
  local blocked = {}
  local aura, text = campBuff()
  if not aura then
    wipe(learnedBlocked)
    return blocked
  end
  local now = GetTime()
  for n, untilT in pairs(learnedBlocked) do
    if untilT > now then blocked[n] = true else learnedBlocked[n] = nil end
  end
  if text == "" then return blocked end
  for _, obj in pairs(CAMP_OBJECTS) do
    if obj.conflicts then
      local names = {}
      for _, n in ipairs(obj.labels or {}) do table.insert(names, n) end
      for _, id in ipairs(obj.items) do
        local n = safe(C_Item.GetItemNameByID, id)
        if n then table.insert(names, n)
        elseif C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
      end
      for _, n in ipairs(names) do
        if text:find(n:lower(), 1, true) then
          for _, c in ipairs(obj.conflicts) do blocked[c:lower()] = true end
          break
        end
      end
    end
  end
  return blocked
end

-- Fehlermeldung "mächtigerer Zauber aktiv" dem zuletzt versuchten Zauber zuordnen
local lastTry = { name = nil, at = 0 }
local lastBounce = 0
local function isBounce(msg)
  if type(msg) ~= "string" or isSecret(msg) then return false end
  if SPELL_FAILED_AURA_BOUNCED and msg == SPELL_FAILED_AURA_BOUNCED then return true end
  local m = msg:lower()
  return m:find("more powerful", 1, true) or m:find("mächtigerer", 1, true) or false
end
local function learnBlock()
  if not lastTry.name or math.abs(lastBounce - lastTry.at) > 1.5 then return end
  local aura = campBuff()
  if not aura then return end
  local exp = aura.expirationTime
  local untilT = (type(exp) == "number" and not isSecret(exp) and exp > 0) and exp or (GetTime() + 3600)
  learnedBlocked[lastTry.name:lower()] = untilT
  lastTry.name = nil
  if ns.queueUpdate then ns.queueUpdate() end
end
local bounceWatch = CreateFrame("Frame")
pcall(bounceWatch.RegisterEvent, bounceWatch, "UI_ERROR_MESSAGE")
pcall(bounceWatch.RegisterUnitEvent, bounceWatch, "UNIT_SPELLCAST_FAILED", "player")
pcall(bounceWatch.RegisterUnitEvent, bounceWatch, "UNIT_SPELLCAST_FAILED_QUIET", "player")
bounceWatch:SetScript("OnEvent", function(_, event, a1, a2, a3)
  if event == "UI_ERROR_MESSAGE" then
    if isBounce(a2) or isBounce(a1) then
      lastBounce = GetTime()
      learnBlock()
    end
  else
    local name = a3 and not isSecret(a3) and safe(C_Spell.GetSpellName, a3)
    if name then
      lastTry.name, lastTry.at = name, GetTime()
      learnBlock()
    end
  end
end)

------------------------------------------------------------------------
-- Anzeige
------------------------------------------------------------------------
-- Der Anker ist ein schmaler Griff LINKS neben den Icons, damit /bc move
-- auch funktioniert, während Icons angezeigt werden.
local HANDLE_W = 14
local anchor = CreateFrame("Frame", "BuffCheckAnchor", UIParent, "BackdropTemplate")
anchor:SetSize(HANDLE_W, ICON_SIZE)
anchor:SetMovable(true)
anchor:EnableMouse(false)
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  BuffCheckDB.pos = { p, rp, x, y }
end)
anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
anchor.bg:SetAllPoints()
anchor.bg:SetColorTexture(0, 0.6, 1, 0.7)
anchor.bg:Hide()
anchor:SetScript("OnEnter", function(self)
  if not self.unlocked then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L["BuffCheck: ziehen zum Verschieben"])
  GameTooltip:AddLine(L["/bc move zum Festsetzen"], 1, 1, 1)
  GameTooltip:Show()
end)
anchor:SetScript("OnLeave", GameTooltip_Hide)
-- Das Setzen von OnEnter schaltet die Maus automatisch an: danach wieder aus
anchor:EnableMouse(false)
anchor.unlocked = false

local queueUpdate -- vorwärts deklariert

local buttons = {}
local function getButton(i)
  local b = buttons[i]
  if b then return b end
  b = CreateFrame("Button", "BuffCheckButton" .. i, anchor, "SecureActionButtonTemplate")
  b:SetSize(ICON_SIZE, ICON_SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b.label:SetWidth(ICON_SIZE + 20)
  b.label:SetWordWrap(false)
  b.craftText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.craftText:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
  b.craftText:SetText(L["craften"])
  b.craftText:SetTextColor(1, 0.5, 0.1)
  b.craftText:Hide()
  -- Cooldown-Spirale (globale Abklingzeit, Item-Cooldowns)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b.icon)
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  -- Grüner Rahmen: frisch hergestellt, jetzt trinken
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetVertexColor(0.2, 1, 0.2)
  b.glow:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
  b.glow:SetPoint("CENTER")
  b.glow:Hide()
  -- Restzeit eines ablaufenden Buffs (oben auf dem Icon)
  b.timeText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.timeText:SetPoint("TOP", b, "TOP", 0, -2)
  b.timeText:SetTextColor(1, 0.85, 0.2)
  b.timeText:Hide()
  -- Gelber Rahmen + Pfeil: schwächerer Ersatz, für das bessere Rezept fehlen Zutaten
  b.weak = b:CreateTexture(nil, "OVERLAY")
  b.weak:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.weak:SetBlendMode("ADD")
  b.weak:SetVertexColor(1, 0.85, 0.1)
  b.weak:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
  b.weak:SetPoint("CENTER")
  b.weak:Hide()
  b.weakArrow = b:CreateTexture(nil, "OVERLAY")
  b.weakArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  b.weakArrow:SetSize(16, 16)
  b.weakArrow:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
  b.weakArrow:Hide()
  -- Herstellbare Anzahl (unten rechts, wie eine Stapelzahl)
  b.countText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.countText:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  b.countText:Hide()
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Fehlt: %s"]:format(self.text or "?"))
    if self.hint then GameTooltip:AddLine(self.hint, 1, 0.82, 0, true) end
    for _, l in ipairs(self.extra or {}) do
      GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 0.82, l[4] or 0, true)
    end
    if self.betterID then
      -- Warum nur der Ersatz? Fehlende Zutaten des besseren Rezepts auflisten
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Schwächerer Ersatz für %s – dafür fehlen:"]:format(
        safe(C_Item.GetItemNameByID, self.betterID) or ("Item " .. self.betterID)), 1, 0.85, 0.1, true)
      for _, r in ipairs(reagentsFor(self.betterID) or {}) do
        local have = safe(C_Item.GetItemCount, r[1]) or 0
        if have < r[2] then
          GameTooltip:AddDoubleLine("  " .. (safe(C_Item.GetItemNameByID, r[1]) or ("Item " .. r[1])),
            ("%d / %d"):format(have, r[2]), 1, 1, 1, 1, 0.25, 0.25)
        end
      end
    end
    if self.craftID then
      local list = reagentsFor(self.craftID)
      if list then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Zutaten:"])
        for _, r in ipairs(list) do
          local have = safe(C_Item.GetItemCount, r[1]) or 0
          local ok = have >= r[2]
          GameTooltip:AddDoubleLine(safe(C_Item.GetItemNameByID, r[1]) or ("Item " .. r[1]),
            ("%d / %d"):format(have, r[2]), 1, 1, 1,
            ok and 0.2 or 1, ok and 1 or 0.25, ok and 0.2 or 0.25)
        end
      end
      GameTooltip:AddLine(" ")
      if self.noReagents then
        GameTooltip:AddLine(L["Zutaten fehlen – Herstellen nicht möglich"], 1, 0.25, 0.25)
      else
        GameTooltip:AddLine(L["Linksklick: herstellen (danach nochmal klicken zum Trinken)"], 1, 1, 1)
      end
      GameTooltip:AddLine(L["Rechtsklick: Rezept im Alchemie-Fenster öffnen"], 0.7, 0.7, 0.7)
    elseif not self.info then
      GameTooltip:AddLine(L["Linksklick: wirken / benutzen"], 1, 1, 1)
    end
    if self.itemID then GameTooltip:AddLine(L["Rechtsklick: Item ignorieren"], 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:HookScript("OnClick", function(self, mouse, down)
    if mouse == "LeftButton" and self:GetAttribute("type1") == "spell" then
      local sp = self:GetAttribute("spell")
      if type(sp) == "string" then lastTry.name, lastTry.at = sp, GetTime() end
    end
    if mouse == "RightButton" and not down and self.craftID then
      openRecipe(self.craftID)
      return
    end
    if mouse == "LeftButton" and self.craftID and self.noReagents then
      if not down then
        chat(L["Zutaten fehlen für %s."]:format(safe(C_Item.GetItemNameByID, self.craftID) or self.craftID))
      end
      return
    end
    if mouse == "LeftButton" and self.craftID and self.recipeSpell then
      -- Rezept wird per Secure-Klick gewirkt – je nach Einstellung schon beim
      -- Drücken (KeyDown). Darum beim ERSTEN der beiden Klick-Events zuschauen.
      local now = GetTime()
      if craftCast.spell and (now - (craftCast.at or 0)) < 1 then return end
      local itemID, spell = self.craftID, self.recipeSpell
      craftCast.spell, craftCast.started, craftCast.at = spell, false, now
      justCrafted[itemID] = true
      C_Timer.After(1, function()
        if craftCast.spell ~= spell then return end
        craftCast.spell = nil
        local casting = UnitCastingInfo and UnitCastingInfo("player")
        if not craftCast.started and not casting then
          chat(L["Konnte nicht herstellen – fehlen Zutaten?"])
        end
      end)
      return
    end
    if mouse == "LeftButton" and not down and self.craftID then
      craftItem(self.craftID)
      return
    end
    if mouse == "RightButton" and not down and self.itemID and not InCombatLockdown() then
      BuffCheckDB.ignored[self.itemID] = true
      chat(L["ignoriere %s (zurückholen: Optionen → Ignorierte Items)"]:format(self.text or self.itemID))
      queueUpdate()
    end
  end)
  buttons[i] = b
  return b
end

------------------------------------------------------------------------
-- Cooldowns
------------------------------------------------------------------------
local function numbers(s, d)
  if type(s) ~= "number" or type(d) ~= "number" or isSecret(s) or isSecret(d) then return nil end
  return s, d
end

local function getCooldown(kind, value)
  if kind == "item" and value then
    local id = tonumber(tostring(value):match("(%d+)"))
    if not id then return nil end
    if C_Container and C_Container.GetItemCooldown then
      return numbers(safe(C_Container.GetItemCooldown, id))
    elseif C_Item and C_Item.GetItemCooldown then
      return numbers(safe(C_Item.GetItemCooldown, id))
    elseif GetItemCooldown then
      return numbers(safe(GetItemCooldown, id))
    end
  elseif kind == "spell" and value then
    if C_Spell and C_Spell.GetSpellCooldown then
      local info = safe(C_Spell.GetSpellCooldown, value)
      if type(info) == "table" then return numbers(info.startTime, info.duration) end
    end
    if GetSpellCooldown then return numbers(safe(GetSpellCooldown, value)) end
  end
  return nil
end

-- Countdown ablaufender Buffs, zweimal pro Sekunde
local function formatTime(s)
  if s >= 60 then return ("%dm"):format(math.ceil(s / 60)) end
  return ("%d"):format(math.max(0, math.ceil(s)))
end
local timeTicker = 0
anchor:SetScript("OnUpdate", function(_, elapsed)
  timeTicker = timeTicker + elapsed
  if timeTicker < 0.5 then return end
  timeTicker = 0
  local now = GetTime()
  for _, b in ipairs(buttons) do
    if b:IsShown() and b.expiresAt and b.expiresAt > now then
      b.timeText:SetText(formatTime(b.expiresAt - now))
      b.timeText:Show()
    else
      b.timeText:Hide()
    end
  end
end)

local function refreshCooldowns()
  for _, b in ipairs(buttons) do
    if b:IsShown() then
      local s, d = getCooldown(b.cdKind, b.cdValue)
      if s and d and d > 0 then
        b.cd:SetCooldown(s, d)
      elseif b.cd.Clear then
        b.cd:Clear()
      else
        b.cd:SetCooldown(0, 0)
      end
    end
  end
end

local function setPosition()
  anchor:ClearAllPoints()
  local p = BuffCheckDB.pos
  if p then
    anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
  end
end

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
queueUpdate = function()
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
ns.queueUpdate = queueUpdate
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
