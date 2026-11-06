-- BuffCheck – Klassenbuffs Jäger (wird nur für Jäger ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "HUNTER" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "dd", "dd", "dd" },
  roles = { "dd" },
  defaultRole = "dd",
  groups = {
    {
      -- Jeder Aspekt zählt als aktiv, vorgeschlagen werden nur Falke und Affe
      key = "jaeger_aspekt", label = L["Aspekt"],
      spells = {
        "Aspekt des Falken", "Aspect of the Hawk", "Aspekt des Affen", "Aspect of the Monkey",
        "Aspekt des Geparden", "Aspect of the Cheetah", "Aspekt des Rudels", "Aspect of the Pack",
        "Aspekt der Wildnis", "Aspect of the Wild", "Aspekt des Wildtiers", "Aspect of the Beast",
      },
      cast = {
        ["Aspekt des Falken"] = true, ["Aspect of the Hawk"] = true,
        ["Aspekt des Affen"] = true, ["Aspect of the Monkey"] = true,
      },
    },
    { key = "jaeger_volltreffer", label = L["Aura des Volltreffers"], spells = { "Aura des Volltreffers", "Trueshot Aura" } },
  },
}
