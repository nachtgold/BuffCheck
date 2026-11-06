-- BuffCheck – Anzeige: Anker, Icon-Buttons, Cooldowns

local ADDON, ns = ...
local L = ns.L

local ICON_SIZE, chat, craftCast, craftItem = ns.ICON_SIZE, ns.chat, ns.craftCast, ns.craftItem
local isSecret, justCrafted, lastTry, openRecipe = ns.isSecret, ns.justCrafted, ns.lastTry, ns.openRecipe
local reagentsFor, safe = ns.reagentsFor, ns.safe

------------------------------------------------------------------------
-- Anzeige
------------------------------------------------------------------------
-- Der Anker ist ein schmaler Griff LINKS neben den Icons, damit /bc move
-- auch funktioniert, während Icons angezeigt werden.
local HANDLE_W = 14
local anchor = CreateFrame("Frame", "BuffCheckAnchor", UIParent, "BackdropTemplate")
anchor:SetSize(HANDLE_W, ICON_SIZE)
anchor:SetMovable(true)
anchor:EnableMouse(false)
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local p, _, rp, x, y = self:GetPoint()
  BuffCheckDB.pos = { p, rp, x, y }
end)
anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
anchor.bg:SetAllPoints()
anchor.bg:SetColorTexture(0, 0.6, 1, 0.7)
anchor.bg:Hide()
anchor:SetScript("OnEnter", function(self)
  if not self.unlocked then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(L["BuffCheck: ziehen zum Verschieben"])
  GameTooltip:AddLine(L["/bc move zum Festsetzen"], 1, 1, 1)
  GameTooltip:Show()
end)
anchor:SetScript("OnLeave", GameTooltip_Hide)
-- Das Setzen von OnEnter schaltet die Maus automatisch an: danach wieder aus
anchor:EnableMouse(false)
anchor.unlocked = false


local buttons = {}
local function getButton(i)
  local b = buttons[i]
  if b then return b end
  b = CreateFrame("Button", "BuffCheckButton" .. i, anchor, "SecureActionButtonTemplate")
  b:SetSize(ICON_SIZE, ICON_SIZE)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
  b.label:SetWidth(ICON_SIZE + 20)
  b.label:SetWordWrap(false)
  b.craftText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.craftText:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
  b.craftText:SetText(L["craften"])
  b.craftText:SetTextColor(1, 0.5, 0.1)
  b.craftText:Hide()
  -- Cooldown-Spirale (globale Abklingzeit, Item-Cooldowns)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cd:SetAllPoints(b.icon)
  if b.cd.SetDrawEdge then b.cd:SetDrawEdge(false) end
  -- Grüner Rahmen: frisch hergestellt, jetzt trinken
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetVertexColor(0.2, 1, 0.2)
  b.glow:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
  b.glow:SetPoint("CENTER")
  b.glow:Hide()
  -- Restzeit eines ablaufenden Buffs (oben auf dem Icon)
  b.timeText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.timeText:SetPoint("TOP", b, "TOP", 0, -2)
  b.timeText:SetTextColor(1, 0.85, 0.2)
  b.timeText:Hide()
  -- Gelber Rahmen + Pfeil: schwächerer Ersatz, für das bessere Rezept fehlen Zutaten
  b.weak = b:CreateTexture(nil, "OVERLAY")
  b.weak:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.weak:SetBlendMode("ADD")
  b.weak:SetVertexColor(1, 0.85, 0.1)
  b.weak:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)
  b.weak:SetPoint("CENTER")
  b.weak:Hide()
  b.weakArrow = b:CreateTexture(nil, "OVERLAY")
  b.weakArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  b.weakArrow:SetSize(16, 16)
  b.weakArrow:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
  b.weakArrow:Hide()
  -- Herstellbare Anzahl (unten rechts, wie eine Stapelzahl)
  b.countText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.countText:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  b.countText:Hide()
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Fehlt: %s"]:format(self.text or "?"))
    if self.hint then GameTooltip:AddLine(self.hint, 1, 0.82, 0, true) end
    for _, l in ipairs(self.extra or {}) do
      GameTooltip:AddLine(l[1], l[2] or 1, l[3] or 0.82, l[4] or 0, true)
    end
    if self.betterID then
      -- Warum nur der Ersatz? Fehlende Zutaten des besseren Rezepts auflisten
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L["Schwächerer Ersatz für %s – dafür fehlen:"]:format(
        safe(C_Item.GetItemNameByID, self.betterID) or ("Item " .. self.betterID)), 1, 0.85, 0.1, true)
      for _, r in ipairs(reagentsFor(self.betterID) or {}) do
        local have = safe(C_Item.GetItemCount, r[1]) or 0
        if have < r[2] then
          GameTooltip:AddDoubleLine("  " .. (safe(C_Item.GetItemNameByID, r[1]) or ("Item " .. r[1])),
            ("%d / %d"):format(have, r[2]), 1, 1, 1, 1, 0.25, 0.25)
        end
      end
    end
    if self.craftID then
      local list = reagentsFor(self.craftID)
      if list then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Zutaten:"])
        for _, r in ipairs(list) do
          local have = safe(C_Item.GetItemCount, r[1]) or 0
          local ok = have >= r[2]
          GameTooltip:AddDoubleLine(safe(C_Item.GetItemNameByID, r[1]) or ("Item " .. r[1]),
            ("%d / %d"):format(have, r[2]), 1, 1, 1,
            ok and 0.2 or 1, ok and 1 or 0.25, ok and 0.2 or 0.25)
        end
      end
      GameTooltip:AddLine(" ")
      if self.noReagents then
        GameTooltip:AddLine(L["Zutaten fehlen – Herstellen nicht möglich"], 1, 0.25, 0.25)
      else
        GameTooltip:AddLine(self.craftLine and L["Linksklick: herstellen (danach nochmal klicken zum Aufstellen)"] or L["Linksklick: herstellen (danach nochmal klicken zum Trinken)"], 1, 1, 1)
      end
      GameTooltip:AddLine(self.craftLine and L["Rechtsklick: Rezept im Berufsfenster öffnen"] or L["Rechtsklick: Rezept im Alchemie-Fenster öffnen"], 0.7, 0.7, 0.7)
    elseif not self.info then
      GameTooltip:AddLine(L["Linksklick: wirken / benutzen"], 1, 1, 1)
    end
    if self.itemID then GameTooltip:AddLine(L["Rechtsklick: Item ignorieren"], 0.7, 0.7, 0.7) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:HookScript("OnClick", function(self, mouse, down)
    if mouse == "LeftButton" and self:GetAttribute("type1") == "spell" then
      local sp = self:GetAttribute("spell")
      if type(sp) == "string" then lastTry.name, lastTry.at = sp, GetTime() end
    end
    if mouse == "RightButton" and not down and self.craftID then
      openRecipe(self.craftID, self.craftLine)
      return
    end
    if mouse == "LeftButton" and self.craftID and self.noReagents then
      if not down then
        chat(L["Zutaten fehlen für %s."]:format(safe(C_Item.GetItemNameByID, self.craftID) or self.craftID))
      end
      return
    end
    if mouse == "LeftButton" and self.craftID and self.recipeSpell then
      -- Rezept wird per Secure-Klick gewirkt – je nach Einstellung schon beim
      -- Drücken (KeyDown). Darum beim ERSTEN der beiden Klick-Events zuschauen.
      local now = GetTime()
      if craftCast.spell and (now - (craftCast.at or 0)) < 1 then return end
      local itemID, spell = self.craftID, self.recipeSpell
      craftCast.spell, craftCast.started, craftCast.at = spell, false, now
      justCrafted[itemID] = true
      C_Timer.After(1, function()
        if craftCast.spell ~= spell then return end
        craftCast.spell = nil
        local casting = UnitCastingInfo and UnitCastingInfo("player")
        if not craftCast.started and not casting then
          chat(L["Konnte nicht herstellen – fehlen Zutaten?"])
        end
      end)
      return
    end
    if mouse == "LeftButton" and not down and self.craftID then
      craftItem(self.craftID, self.craftLine)
      return
    end
    if mouse == "RightButton" and not down and self.itemID and not InCombatLockdown() then
      BuffCheckDB.ignored[self.itemID] = true
      chat(L["ignoriere %s (zurückholen: Optionen → Ignorierte Items)"]:format(self.text or self.itemID))
      ns.queueUpdate()
    end
  end)
  buttons[i] = b
  return b
end

------------------------------------------------------------------------
-- Cooldowns
------------------------------------------------------------------------
local function numbers(s, d)
  if type(s) ~= "number" or type(d) ~= "number" or isSecret(s) or isSecret(d) then return nil end
  return s, d
end

local function getCooldown(kind, value)
  if kind == "item" and value then
    local id = tonumber(tostring(value):match("(%d+)"))
    if not id then return nil end
    if C_Container and C_Container.GetItemCooldown then
      return numbers(safe(C_Container.GetItemCooldown, id))
    elseif C_Item and C_Item.GetItemCooldown then
      return numbers(safe(C_Item.GetItemCooldown, id))
    elseif GetItemCooldown then
      return numbers(safe(GetItemCooldown, id))
    end
  elseif kind == "spell" and value then
    if C_Spell and C_Spell.GetSpellCooldown then
      local info = safe(C_Spell.GetSpellCooldown, value)
      if type(info) == "table" then return numbers(info.startTime, info.duration) end
    end
    if GetSpellCooldown then return numbers(safe(GetSpellCooldown, value)) end
  end
  return nil
end

-- Countdown ablaufender Buffs, zweimal pro Sekunde
local function formatTime(s)
  if s >= 60 then return ("%dm"):format(math.ceil(s / 60)) end
  return ("%d"):format(math.max(0, math.ceil(s)))
end
local timeTicker = 0
anchor:SetScript("OnUpdate", function(_, elapsed)
  timeTicker = timeTicker + elapsed
  if timeTicker < 0.5 then return end
  timeTicker = 0
  local now = GetTime()
  for _, b in ipairs(buttons) do
    if b:IsShown() and b.expiresAt and b.expiresAt > now then
      b.timeText:SetText(formatTime(b.expiresAt - now))
      b.timeText:Show()
    else
      b.timeText:Hide()
    end
  end
end)

local function refreshCooldowns()
  for _, b in ipairs(buttons) do
    if b:IsShown() then
      local s, d = getCooldown(b.cdKind, b.cdValue)
      if s and d and d > 0 then
        b.cd:SetCooldown(s, d)
      elseif b.cd.Clear then
        b.cd:Clear()
      else
        b.cd:SetCooldown(0, 0)
      end
    end
  end
end

local function setPosition()
  anchor:ClearAllPoints()
  local p = BuffCheckDB.pos
  if p then
    anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
  end
end

-- Für die anderen Module
ns.anchor = anchor
ns.buttons = buttons
ns.getButton = getButton
ns.numbers = numbers
ns.getCooldown = getCooldown
ns.formatTime = formatTime
ns.refreshCooldowns = refreshCooldowns
ns.setPosition = setPosition
