-- BuffCheck – Klassenbuffs Schamane (wird nur für Schamanen ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "SHAMAN" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "caster", "dd", "heal" }, -- Elementar, Verstärkung, Wiederherstellung
  roles = { "heal", "dd", "caster" },
  defaultRole = "caster",
  groups = {
    { key = "schamane_schild", label = L["Blitzschlagschild"], spells = { "Blitzschlagschild", "Lightning Shield" } },
    {
      -- Waffenverzauberung (Waffenhand): zuletzt benutzte zuerst, sonst die erste bekannte
      key = "schamane_waffe", label = L["Waffenverzauberung"],
      weapon = {
        slots = { 16 },
        spells = {
          "Waffe des Windzorns", "Windfury Weapon", "Waffe der Flammenzunge", "Flametongue Weapon",
          "Waffe des Felsbeißers", "Rockbiter Weapon", "Waffe des Frostbrands", "Frostbrand Weapon",
        },
      },
    },
  },
}
