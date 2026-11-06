-- BuffCheck – Klassenbuffs Hexenmeister (wird nur für Hexenmeister ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "WARLOCK" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "caster", "caster", "caster" },
  roles = { "caster" },
  defaultRole = "caster",
  groups = {
    {
      key = "hexer_ruestung", label = L["Dämonenrüstung"],
      spells = { "Dämonenrüstung", "Demon Armor", "Dämonenhaut", "Demon Skin" },
    },
  },
}
