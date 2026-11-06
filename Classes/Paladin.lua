-- BuffCheck – Klassenbuffs Paladin (wird nur für Paladine ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "PALADIN" then return end
local L = ns.L

ns.CLASS = {
  roleByTab = { "heal", "tank", "dd" }, -- Heilig, Schutz, Vergeltung
  roles = { "heal", "tank", "dd" },
  defaultRole = "dd",
  groups = {
    {
      key = "segen", label = L["Segen"],
      spells = {
        "Großer Segen der Könige", "Segen der Könige",
        "Großer Segen der Macht", "Segen der Macht",
        "Großer Segen der Weisheit", "Segen der Weisheit",
        "Großer Segen des Lichts", "Segen des Lichts",
        "Großer Segen des Refugiums", "Segen des Refugiums",
        "Greater Blessing of Kings", "Blessing of Kings",
        "Greater Blessing of Might", "Blessing of Might",
        "Greater Blessing of Wisdom", "Blessing of Wisdom",
        "Greater Blessing of Light", "Blessing of Light",
        "Greater Blessing of Sanctuary", "Blessing of Sanctuary",
      },
    },
    {
      key = "aura", label = L["Aura"],
      spells = {
        "Aura der Hingabe", "Vergeltungsaura", "Konzentrationsaura",
        "Aura der Heiligkeit", "Aura des Schattenwiderstands",
        "Aura des Frostwiderstands", "Aura des Feuerwiderstands",
        "Devotion Aura", "Retribution Aura", "Concentration Aura",
        "Sanctity Aura", "Shadow Resistance Aura",
        "Frost Resistance Aura", "Fire Resistance Aura",
      },
    },
    {
      key = "zorn", label = L["Zorn d. Gerechtigkeit"], defaultOff = true,
      spells = { "Zorn der Gerechtigkeit", "Righteous Fury" },
    },
  },
}
