-- BuffCheck – Klassenbuffs Schurke (wird nur für Schurken ausgeführt)
local _, ns = ...
if select(2, UnitClass("player")) ~= "ROGUE" then return end
local L = ns.L

-- Gifte werden am Namen in der Tasche erkannt (höchster Rang zuerst)
local INSTANT = { "sofort wirkendes gift", "instant poison" }
local DEADLY = { "tödliches gift", "deadly poison" }
local WOUND = { "wundgift", "wound poison" }
local CRIPPLING = { "verkrüppelndes gift", "crippling poison" }
local MIND = { "gedankenbetäubendes gift", "mind-numbing poison" }

ns.CLASS = {
  roleByTab = { "dd", "dd", "dd" },
  roles = { "dd" },
  defaultRole = "dd",
  groups = {
    {
      key = "schurke_gift", label = L["Gift"],
      weapon = {
        slots = { 16, 17 },
        labels = { [16] = L["Gift (Waffenhand)"], [17] = L["Gift (Schildhand)"] },
        items = {
          [16] = { INSTANT, DEADLY, WOUND, CRIPPLING, MIND },
          [17] = { DEADLY, INSTANT, CRIPPLING, WOUND, MIND },
        },
      },
    },
  },
}
