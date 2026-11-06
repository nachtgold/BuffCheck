-- BuffCheck – Klassenbuffs Priester (wird nur für Priester ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "PRIEST" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "heal", "heal", "caster" }, -- Disziplin, Heilig, Schatten
  roles = { "heal", "caster" },
  defaultRole = "heal",
  groups = {
    {
      key = "priester_ausdauer", label = L["Seelenstärke"],
      spells = { "Machtwort: Seelenstärke", "Power Word: Fortitude", "Gebet der Seelenstärke", "Prayer of Fortitude" },
    },
    { key = "priester_feuer", label = L["Inneres Feuer"], spells = { "Inneres Feuer", "Inner Fire" } },
    {
      key = "priester_wille", label = L["Göttlicher Willen"],
      spells = { "Göttlicher Willen", "Divine Spirit", "Gebet der Willenskraft", "Prayer of Spirit" },
    },
    {
      key = "priester_schatten", label = L["Schattenschutz"], defaultOff = true,
      spells = { "Schattenschutz", "Shadow Protection", "Gebet des Schattenschutzes", "Prayer of Shadow Protection" },
    },
    { key = "priester_gestalt", label = L["Schattengestalt"], spells = { "Schattengestalt", "Shadowform" } },
  },
}
