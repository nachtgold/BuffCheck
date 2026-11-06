-- BuffCheck – Hilfsfunktionen: sichere API-Aufrufe, Buff-Abfragen

local ADDON, ns = ...
local L = ns.L

local ICON_SIZE = 40
local REFRESH_BELOW = 30      -- Sekunden Restlaufzeit, ab der ein Buff als "fehlt" gilt
local MIN_BUFF_MINUTES = 10   -- Verbrauchsgüter mit kürzerer Wirkung (Heiltränke etc.) ignorieren

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

-- Für die anderen Module
ns.ICON_SIZE = ICON_SIZE
ns.REFRESH_BELOW = REFRESH_BELOW
ns.MIN_BUFF_MINUTES = MIN_BUFF_MINUTES
ns.isSecret = isSecret
ns.safe = safe
ns.knownSpell = knownSpell
ns.warnBefore = warnBefore
ns.auraRemaining = auraRemaining
ns.judge = judge
ns.hasBuff = hasBuff
ns.hasSpellBuff = hasSpellBuff
ns.hasAnyBuff = hasAnyBuff
