-- BuffCheck – Klassenbuffs Druide (wird nur für Druiden ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "DRUID" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "caster", "dd", "heal" }, -- Gleichgewicht, Wilder Kampf, Wiederherstellung
  roles = { "heal", "tank", "dd", "caster" },
  defaultRole = "caster",
  groups = {
    {
      key = "druide_mal", label = L["Mal der Wildnis"],
      spells = { "Mal der Wildnis", "Mark of the Wild", "Gabe der Wildnis", "Gift of the Wild" },
    },
    { key = "druide_dornen", label = L["Dornen"], defaultOff = true, spells = { "Dornen", "Thorns" } },
    { key = "druide_omen", label = L["Omen der Klarsicht"], spells = { "Omen der Klarsicht", "Omen of Clarity" } },
  },
}
