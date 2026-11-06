-- BuffCheck – Klassenbuffs Magier (wird nur für Magier ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "MAGE" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "caster", "caster", "caster" },
  roles = { "caster" },
  defaultRole = "caster",
  groups = {
    {
      key = "magier_int", label = L["Arkane Intelligenz"],
      spells = { "Arkane Intelligenz", "Arcane Intellect", "Arkane Brillanz", "Arcane Brilliance" },
    },
    {
      key = "magier_ruestung", label = L["Rüstung"],
      spells = { "Magische Rüstung", "Mage Armor", "Eisrüstung", "Ice Armor", "Frostrüstung", "Frost Armor" },
    },
  },
}
