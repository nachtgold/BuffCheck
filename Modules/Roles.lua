-- BuffCheck – Alchemie-Skill und Rolle (pro Charakter)

local ADDON, ns = ...
local L = ns.L

local ALCHEMY_NAMES, ALCHEMY_SKILLLINE, ROLE_SLOTS, isSecret = ns.ALCHEMY_NAMES, ns.ALCHEMY_SKILLLINE, ns.ROLE_SLOTS, ns.isSecret
local safe = ns.safe
local CLASS = ns.CLASS or { groups = {}, roleByTab = {}, roles = { "dd" }, defaultRole = "dd" }

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

-- Für die anderen Module
ns.CLASS = CLASS
ns.alchemySkill = alchemySkill
ns.ROLE_BY_TAB = ROLE_BY_TAB
ns.CLASS_ROLE = CLASS_ROLE
ns.roleKey = roleKey
ns.getRole = getRole
ns.setRole = setRole
ns.currentRole = currentRole
