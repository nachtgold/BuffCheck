-- BuffCheck – Lagerfeuer: Lagerobjekt vorschlagen, Lager-Buff auslesen

local ADDON, ns = ...
local L = ns.L

local craftCount, currentRole, hasBuff, inBags = ns.craftCount, ns.currentRole, ns.hasBuff, ns.inBags
local isSecret, recipeFor, safe = ns.isSecret, ns.recipeFor, ns.safe

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
  alchimie = { line = 171, labels = { "Manabrunnen", "Mana Well" }, names = { "alchemie", "alchemy" }, effect = L["Mana alle 5 Sek."],
    items = { 279990, 279970, 279956 },
    conflicts = { "Segen der Weisheit", "Großer Segen der Weisheit", "Blessing of Wisdom", "Greater Blessing of Wisdom" } },
  schmiede = { line = 164, labels = { "Schleifstein", "Sharpening Wheel" }, names = { "schmiedekunst", "blacksmithing" }, effect = L["Stärke"],
    items = { 279955, 279988, 279944 },
    conflicts = { "Stärke der Erde", "Strength of Earth" } },
  verzauber = { line = 333, labels = { "Verzauberte Laute", "Enchanted Lute" }, names = { "verzauberkunst", "enchanting" }, effect = L["Rüstung und alle Werte"],
    items = { 279987, 279985, 279976 },
    conflicts = { "Mal der Wildnis", "Gabe der Wildnis", "Mark of the Wild", "Gift of the Wild" } },
  ingenieur = { line = 202, names = { "ingenieurskunst", "engineering" }, effect = L["Reagenzien und Reparatur (kein Buff)"],
    items = { 279989, 279949, 279950 }, noBuff = true },
  kraeuter = { line = 182, labels = { "Räucherkerze", "Incense Candle" }, names = { "kräuterkunde", "herbalism" }, effect = L["Intelligenz"],
    items = { 279947, 279964, 279962 },
    conflicts = { "Arkane Intelligenz", "Arkane Brillanz", "Arcane Intellect", "Arcane Brilliance" } },
  leder = { line = 165, names = { "lederverarbeitung", "leatherworking" }, effect = L["Ruhebonus (Erfahrung)"],
    items = { 279945, 279941, 279978 } },
  bergbau = { line = 186, labels = { "Leitstein", "Lodestone" }, names = { "bergbau", "mining" }, effect = L["Angriffskraft"],
    items = { 279952, 279948, 279960 },
    conflicts = { "Segen der Macht", "Großer Segen der Macht", "Blessing of Might", "Greater Blessing of Might" } },
  kuerschner = { line = 393, labels = { "Lagerstuhl", "Camp Chair" }, names = { "kürschnerei", "skinning" }, effect = L["2 % kritische Trefferchance"],
    items = { 279938, 279969, 279979 },
    conflicts = { "Aura des Moonkin", "Moonkin-Aura", "Moonkin Aura" } },
  schneider = { line = 197, labels = { "Fraktionsbanner", "Faction Banner" }, names = { "schneiderei", "tailoring" }, effect = L["Willenskraft"],
    items = { 279959, 279943, 279972 },
    conflicts = { "Göttlicher Willen", "Gebet der Willenskraft", "Divine Spirit", "Prayer of Spirit" } },
  erstehilfe = { line = 129, labels = { "Verbandtasche", "First Aid Kit" }, names = { "erste hilfe", "first aid" }, effect = L["Ausdauer"],
    items = { 279951, 279940, 279968 },
    conflicts = { "Machtwort: Seelenstärke", "Gebet der Seelenstärke", "Power Word: Fortitude", "Prayer of Fortitude" } },
  angeln = { line = 356, labels = { "Fischglas", "Fish Bowl" }, names = { "angeln", "fishing" }, effect = L["8 % auf alle Werte"],
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

-- Lager-Buff (Camp Benefits) am Namen erkennen
local CAMP_AURA_PATTERNS = { "lagerfeuer", "campfire", "lager", "camp" }
-- Buff "Campfire Nearby": nur damit werden Lagerobjekte vorgeschlagen
local CAMP_NEARBY_SPELL = 1283391
local CAMP_NEARBY_NAMES = { "Campfire Nearby", "Lagerfeuer in der Nähe" }

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

local function matchesAny(text, patterns)
  if not text or isSecret(text) then return false end
  text = text:lower()
  for _, p in ipairs(patterns) do
    if text:find(p, 1, true) then return true end
  end
  return false
end

-- Bist du an einem Lagerfeuer? Nur der Buff "Campfire Nearby" zählt; ohne ihn
-- werden keine Lagerobjekte vorgeschlagen. Liefert eine Begründung (/bc lager).
local function nearCampfire()
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, CAMP_NEARBY_SPELL)
    if ok and aura and not isSecret(aura) then
      return true, L["Buff: %s"]:format(aura.name or "Campfire Nearby")
    end
  end
  for _, n in ipairs(CAMP_NEARBY_NAMES) do
    local active, rem = hasBuff(n) -- rem: Buff da, läuft nur bald ab
    if active or rem then return true, L["Buff: %s"]:format(n) end
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
    -- Beste Stufe, deren Rezept du kennst; sonst Stufe 1 (gleiche Stärkung)
    local id = pick.obj.items[#pick.obj.items]
    for _, tid in ipairs(pick.obj.items) do
      if recipeFor(tid) then id = tid break end
    end
    -- Klick: Berufsfenster öffnen, herstellen, Fenster schließen (wie Alchemie)
    table.insert(missing, {
      text = L["Lager"], icon = safe(C_Item.GetItemIconByID, id),
      craft = true, craftID = id, craftLine = pick.obj.line,
      craftCount = craftCount(id),
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

-- Für die anderen Module
ns.CAMP_OBJECTS = CAMP_OBJECTS
ns.CAMP_TIER1_SKILL = CAMP_TIER1_SKILL
ns.CAMP_PRIORITY = CAMP_PRIORITY
ns.CAMP_KITS = CAMP_KITS
ns.CAMP_ITEM = CAMP_ITEM
ns.CAMP_AURA_PATTERNS = CAMP_AURA_PATTERNS
ns.CAMP_NEARBY_SPELL = CAMP_NEARBY_SPELL
ns.CAMP_NEARBY_NAMES = CAMP_NEARBY_NAMES
ns.professionSkills = professionSkills
ns.campSkill = campSkill
ns.matchesAny = matchesAny
ns.nearCampfire = nearCampfire
ns.campRole = campRole
ns.campOnCooldown = campOnCooldown
ns.campBuff = campBuff
ns.campObjectInText = campObjectInText
ns.campCandidates = campCandidates
ns.campItemName = campItemName
ns.collectCamp = collectCamp
ns.scanBuffTooltip = scanBuffTooltip
ns.learnedBlocked = learnedBlocked
ns.campBlockedSpells = campBlockedSpells
ns.lastTry = lastTry
ns.isBounce = isBounce
ns.learnBlock = learnBlock
