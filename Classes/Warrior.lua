-- BuffCheck – Klassenbuffs Krieger (wird nur für Krieger ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "WARRIOR" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "dd", "dd", "tank" }, -- Waffen, Furor, Schutz
  roles = { "dd", "tank" },
  defaultRole = "dd",
  groups = {
    -- Standardmäßig aus: braucht Wut, die du außerhalb des Kampfs meist nicht hast
    { key = "krieger_ruf", label = L["Schlachtruf"], defaultOff = true, spells = { "Schlachtruf", "Battle Shout" } },
  },
}
