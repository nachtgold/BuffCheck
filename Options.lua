-- BuffCheck – Einstellungen (in der AddOn-Übersicht des Spiels) und Minimap-Button
-- Linksklick auf den Minimap-Button: Einstellungen, Rechtsklick: Icons verschieben,
-- Ziehen: Button um die Minimap bewegen.

local ADDON, ns = ...
local L = ns.L

local ICON = "Interface\\Icons\\INV_Potion_62"

-- Beschriftung der Elixier-Slots
local SLOT_TEXT = {
  flask      = L["Fläschchen"],
  flask_heal = L["Fläschchen (Weisheit)"],
  flask_tank = L["Fläschchen (Titanen)"],
  flask_caster = L["Fläschchen (Oberste Macht)"],
  staerke    = L["Stärke"],
  bew        = L["Beweglichkeit"],
  angriff    = L["Angriffskraft"],
  zauber     = L["Zauberschaden"],
  leben      = L["Gesundheit"],
  ruestung   = L["Rüstung"],
  regen      = L["Leben-Regeneration"],
  heilung    = L["Heilung"],
  manareg    = L["Mana-Regeneration"],
  int        = L["Intelligenz"],
}

-- Alle Rollen; angezeigt werden "Alle", "Auto" und die Rollen deiner Klasse
local ROLES = {
  { "alle",   L["Alle"],     L["Jedes Elixier, das du herstellen kannst"] },
  { "auto",   L["Auto"],     L["Nach dem Talentbaum mit den meisten Punkten"] },
  { "heal",   L["Heiler"],   L["Fläschchen, Heilung, Mana-Reg., Intelligenz"] },
  { "tank",   L["Tank"],     L["Fläschchen, Gesundheit, Rüstung, Stärke"] },
  { "dd",     L["Nahkampf"], L["Fläschchen, Stärke, Beweglichkeit, Angriffskraft"] },
  { "caster", L["Zauberer"], L["Fläschchen, Zauberschaden, Intelligenz, Mana-Reg."] },
}

------------------------------------------------------------------------
-- Bausteine
------------------------------------------------------------------------
local panel, category
local widgets = {}   -- alles mit :refresh()
local slotBoxes = {} -- wiederverwendbare Checkboxen für Elixier-Slots

local function refreshAll()
  if not panel or not panel:IsVisible() then return end
  for _, w in ipairs(widgets) do w.refresh() end
end

local function changed()
  ns.queueUpdate()
  refreshAll()
end

local function tooltip(frame, text)
  if not text then return end
  frame:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:HookScript("OnLeave", GameTooltip_Hide)
end

local function setDimmed(frame, dimmed)
  frame:SetAlpha(dimmed and 0.45 or 1)
  if frame.SetEnabled then frame:SetEnabled(not dimmed) end
end

local function header(parent, y, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", 18, y)
  fs:SetText(text)
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 0.82, 0, 0.25)
  line:SetHeight(1)
  line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
  line:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
  return fs
end

local function checkbox(parent, x, y, label, get, set, tip, dimWhen)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", x, y)
  cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  cb.label:SetText(label)
  cb:SetHitRectInsets(0, -(cb.label:GetStringWidth() + 4), 0, 0)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    changed()
  end)
  tooltip(cb, tip)
  cb.refresh = function()
    cb:SetChecked(get() and true or false)
    if dimWhen then setDimmed(cb, dimWhen()) end
  end
  table.insert(widgets, cb)
  return cb
end

local function button(parent, x, y, w, label, onClick, tip)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  tooltip(b, tip)
  return b
end

-- Eigener Schieberegler (ohne Template-Abhängigkeit)
local function slider(parent, x, y, label, minV, maxV, step, get, set, unit)
  local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", x, y + 18)

  local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
  s:SetOrientation("HORIZONTAL")
  s:SetSize(200, 16)
  s:SetPoint("TOPLEFT", x, y)
  s:SetBackdrop({
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 },
  })
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  s:EnableMouseWheel(true)

  local low = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 0)
  low:SetText(minV)
  local high = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 0)
  high:SetText(maxV)

  local function show(v) title:SetText(("%s: |cffffffff%d%s|r"):format(label, v, unit or "")) end

  s:SetScript("OnValueChanged", function(self, v)
    v = math.floor(v / step + 0.5) * step
    show(v)
    if self.silent then return end
    if get() ~= v then
      set(v)
      ns.queueUpdate()
    end
  end)
  s:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(math.min(maxV, math.max(minV, self:GetValue() + delta * step)))
  end)
  s.refresh = function()
    s.silent = true
    s:SetValue(get())
    s.silent = false
    show(get())
  end
  table.insert(widgets, s)
  return s
end

local function alchemyOff() return not BuffCheckDB.enabled.alchemie end

------------------------------------------------------------------------
-- Inhalt der Einstellungsseite
------------------------------------------------------------------------
local CONTENT_HEIGHT = 844

local function buildContent(f)
  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", 18, -12)
  title:SetText("BuffCheck")
  local sub = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("LEFT", title, "RIGHT", 10, -2)
  sub:SetText(L["Fehlende Buffs im Blick – Klick zum Wirken, Benutzen oder Herstellen"])

  local Y = -26 -- alles unter dem Titel

  -- Anzeige ------------------------------------------------------------
  header(f, Y - 34, L["Anzeige"])
  checkbox(f, 20, Y - 56, L["Auf Reittier ausblenden"],
    function() return BuffCheckDB.hideMounted end,
    function(v) BuffCheckDB.hideMounted = v end)
  checkbox(f, 20, Y - 80, L["Minimap-Button anzeigen"],
    function() return BuffCheckDB.minimap.show end,
    function(v) BuffCheckDB.minimap.show = v; ns.UpdateMinimapButton() end,
    L["Ausgeblendet? Mit /bc minimap kommt er zurück. /bc öffnet diese Einstellungen."])
  local moveBtn = button(f, 320, Y - 58, 180, L["Icons verschieben"], function()
    ns.setMoving(not ns.isMoving())
    refreshAll()
  end, L["Zeigt links neben den Icons einen blauen Griff zum Ziehen. Nochmal klicken zum Festsetzen."])
  moveBtn.refresh = function()
    moveBtn:SetText(ns.isMoving() and L["Position festsetzen"] or L["Icons verschieben"])
  end
  table.insert(widgets, moveBtn)

  -- Icon-Leiste --------------------------------------------------------
  header(f, Y - 116, L["Icon-Leiste"])
  checkbox(f, 20, Y - 138, L["Buff-Namen unter den Icons anzeigen"],
    function() return BuffCheckDB.showLabels end,
    function(v) BuffCheckDB.showLabels = v end,
    L["Der Tooltip zeigt den Namen ohnehin an."])
  checkbox(f, 20, Y - 162, L["Hinweis \"craften\" / \"trinken\" auf den Icons"],
    function() return BuffCheckDB.showCraftText end,
    function(v) BuffCheckDB.showCraftText = v end,
    L["Auch ohne Text: graues Icon = erst herstellen, farbiges Icon = benutzen."])
  slider(f, 24, Y - 204, L["Abstand"], 0, 40, 1,
    function() return BuffCheckDB.grid.gap end,
    function(v) BuffCheckDB.grid.gap = v end, " px")
  slider(f, 254, Y - 204, L["Icons pro Zeile"], 1, 20, 1,
    function() return BuffCheckDB.grid.perRow end,
    function(v) BuffCheckDB.grid.perRow = v end, "")
  local warn = slider(f, 24, Y - 254, L["Vorwarnung vor Ablauf"], 0, 300, 15,
    function() return BuffCheckDB.warnBefore end,
    function(v) BuffCheckDB.warnBefore = v end, " s")
  tooltip(warn, L["Ein Buff erscheint schon, wenn er nur noch so viele Sekunden läuft. Die Restzeit steht oben auf dem Icon."])

  -- Klassenbuffs -------------------------------------------------------
  header(f, Y - 300, L["Klassenbuffs"])
  -- 3 pro Zeile; jede weitere Zeile schiebt den Rest der Seite nach unten
  for i, g in ipairs(ns.GROUPS) do
    local key = g.key
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    checkbox(f, 20 + col * 190, Y - 322 - row * 24, g.label,
      function() return BuffCheckDB.enabled[key] end,
      function(v) BuffCheckDB.enabled[key] = v end)
  end
  local extraRows = math.max(0, math.ceil(#ns.GROUPS / 3) - 1)
  Y = Y - extraRows * 24
  CONTENT_HEIGHT = CONTENT_HEIGHT + extraRows * 24

  -- Verbrauchsgüter ----------------------------------------------------
  header(f, Y - 360, L["Verbrauchsgüter"])
  checkbox(f, 20, Y - 382, L["Buff-Essen (\"Satt\")"],
    function() return BuffCheckDB.enabled.essen end,
    function(v) BuffCheckDB.enabled.essen = v end,
    L["Zeigt dein Buff-Essen, wenn \"Satt\" fehlt. Bevorzugtes Essen: /bc food [Link]"])
  checkbox(f, 300, Y - 382, L["Lagerfeuer"],
    function() return BuffCheckDB.enabled.lager end,
    function(v) BuffCheckDB.enabled.lager = v end,
    L["Am Lagerfeuer: schlägt das Lagerobjekt vor, das du selbst aufstellen solltest (nach Rolle, Beruf und Klassenbuffs). Prüfen: /bc lager"])
  checkbox(f, 20, Y - 406, L["Sonstige Buff-Items aus den Taschen"],
    function() return BuffCheckDB.enabled.elixier end,
    function(v) BuffCheckDB.enabled.elixier = v end,
    L["Elixiere, Rollen usw., die du dabei hast und deren Buff fehlt."])

  -- Alchemie -----------------------------------------------------------
  header(f, Y - 444, L["Alchemie"])
  local status = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  status:SetPoint("TOPLEFT", 24, Y - 466)
  status.refresh = function()
    local known = ns.knownRecipes()
    status:SetText(L["Alchemie-Skill: %d   ·   Rezepte: %s"]:format(ns.alchemySkill(),
      known and L["aus Alchemie-Fenster gemerkt"] or L["noch nicht gemerkt – Alchemie-Fenster einmal öffnen"]))
  end
  table.insert(widgets, status)

  checkbox(f, 20, Y - 482, L["Herstellbare Elixiere als gebraucht anzeigen"],
    function() return BuffCheckDB.enabled.alchemie end,
    function(v) BuffCheckDB.enabled.alchemie = v end,
    L["Elixiere, die du als Alchemist herstellen kannst, erscheinen, sobald ihr Buff fehlt."])
  checkbox(f, 20, Y - 506, L["Auch anzeigen, wenn nicht in der Tasche (\"craften\")"],
    function() return BuffCheckDB.alchShowCraft end,
    function(v) BuffCheckDB.alchShowCraft = v end,
    L["Graues Icon: Klick stellt das Elixier her."], alchemyOff)
  checkbox(f, 20, Y - 530, L["Schwächere Rezepte als Ersatz anzeigen"],
    function() return BuffCheckDB.alchFallback end,
    function(v) BuffCheckDB.alchFallback = v end,
    L["Fehlen Zutaten für das beste Rezept, wird ein schwächeres angezeigt, für das du Zutaten hast (gelber Rahmen mit Pfeil). Aus: das beste Rezept bleibt rot mit 0."], alchemyOff)

  local roleLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  roleLabel:SetPoint("TOPLEFT", 24, Y - 564)
  roleLabel:SetText(L["Rolle:"])
  local rx = 90
  local classRole = { alle = true, auto = true }
  for _, k in ipairs(ns.CLASS_ROLES) do classRole[k] = true end
  for _, r in ipairs(ROLES) do
    if classRole[r[1]] then
      local key = r[1]
      local rb = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
      rb:SetSize(16, 16)
      rb:SetPoint("TOPLEFT", rx, Y - 563)
      rb.label = rb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      rb.label:SetPoint("LEFT", rb, "RIGHT", 2, 0)
      rb.label:SetText(r[2])
      rb:SetHitRectInsets(0, -(rb.label:GetStringWidth() + 4), 0, 0)
      rb:SetScript("OnClick", function()
        ns.setRole(key)
        changed()
      end)
      tooltip(rb, r[3])
      rb.refresh = function()
        rb:SetChecked(ns.getRole() == key)
        setDimmed(rb, alchemyOff())
      end
      table.insert(widgets, rb)
      rx = rx + rb.label:GetStringWidth() + 32
    end
  end

  local slotLabel = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  slotLabel:SetPoint("TOPLEFT", 24, Y - 592)
  slotLabel.refresh = function()
    local role = ns.currentRole()
    slotLabel:SetText(L["Elixiere für %s:"]:format(ns.ROLE_NAMES[role] or role))
  end
  table.insert(widgets, slotLabel)

  -- Slot-Checkboxen: werden je nach Rolle neu belegt
  local slotHolder = { refresh = function()
    local keys = ns.ROLE_SLOTS[ns.currentRole()] or {}
    for i, key in ipairs(keys) do
      local cb = slotBoxes[i]
      if not cb then
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", 20 + col * 170, Y - 612 - row * 24)
        cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 1)
        cb:SetHitRectInsets(0, -130, 0, 0)
        cb:SetScript("OnClick", function(self)
          BuffCheckDB.enabled["alch_" .. self.key] = self:GetChecked() and true or false
          changed()
        end)
        cb:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:AddLine(SLOT_TEXT[self.key] or self.key)
          for _, e in ipairs(ns.ALCH_SLOTS[self.key].list) do
            local name = ns.safe(C_Item.GetItemNameByID, e[1]) or ("Item " .. e[1])
            GameTooltip:AddDoubleLine(name, L["Skill %d"]:format(e[3]), 1, 1, 1, 0.6, 0.6, 0.6)
          end
          GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
        slotBoxes[i] = cb
      end
      cb.key = key
      cb.label:SetText(SLOT_TEXT[key] or key)
      cb:SetChecked(BuffCheckDB.enabled["alch_" .. key] ~= false)
      setDimmed(cb, alchemyOff())
      cb:Show()
    end
    for i = #keys + 1, #slotBoxes do slotBoxes[i]:Hide() end
  end }
  table.insert(widgets, slotHolder)

  -- Ignorierliste ------------------------------------------------------
  header(f, Y - 720, L["Ignorierte Items"])
  local ignText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  ignText:SetPoint("TOPLEFT", 24, Y - 748)
  ignText.refresh = function()
    local n = 0
    for _ in pairs(BuffCheckDB.ignored) do n = n + 1 end
    ignText:SetText(n == 0 and L["Keine (Rechtsklick auf ein Icon ignoriert es)"]
      or L["%d Item(s) ignoriert"]:format(n))
  end
  table.insert(widgets, ignText)

  local clearBtn = button(f, 20, Y - 770, 160, L["Liste leeren"], function()
    ns.resetIgnored()
    ns.say(L["Ignorierliste geleert."])
    refreshAll()
  end)
  clearBtn:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Ignoriert:"])
    local any = false
    for id in pairs(BuffCheckDB.ignored) do
      any = true
      GameTooltip:AddLine(ns.safe(C_Item.GetItemNameByID, id) or ("Item " .. id), 1, 1, 1)
    end
    if not any then GameTooltip:AddLine(L["nichts"], 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  clearBtn:HookScript("OnLeave", GameTooltip_Hide)
  button(f, 190, Y - 770, 180, L["Taschen neu scannen"], function()
    ns.rescan()
    ns.say(L["Taschen werden neu geprüft."])
  end, L["Hilft, wenn ein neues Buff-Item nicht erkannt wurde."])
end

-- Seite: scrollbarer Bereich, damit alles auch bei kleiner UI-Skalierung passt
local function createPanel()
  local p = CreateFrame("Frame", "BuffCheckOptions")
  p.name = "BuffCheck" -- für die alte Interface-Optionen-API

  local scroll = CreateFrame("ScrollFrame", "BuffCheckOptionsScroll", p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -28, 4)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(600, CONTENT_HEIGHT)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnSizeChanged", function(self, w)
    if w and w > 0 then content:SetWidth(w) end
  end)

  buildContent(content)
  content:SetHeight(CONTENT_HEIGHT) -- kann sich durch mehr Klassenbuffs erhöhen
  p:SetScript("OnShow", function() C_Timer.After(0, refreshAll) end)
  return p
end

local function register()
  if panel then return end
  panel = createPanel()
  if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, "BuffCheck")
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

function ns.ToggleOptions()
  register()
  if category and Settings and Settings.OpenToCategory then
    if SettingsPanel and SettingsPanel:IsShown() and panel:IsVisible() then
      HideUIPanel(SettingsPanel)
    else
      Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
    end
  elseif InterfaceOptionsFrame_OpenToCategory then
    -- alte API braucht den Aufruf zweimal, um sicher die richtige Seite zu zeigen
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end

-- Addon-Menü (Kompass-Symbol an der Minimap), falls vorhanden
function BuffCheck_OnAddonCompartmentClick()
  ns.ToggleOptions()
end

------------------------------------------------------------------------
-- Minimap-Button
------------------------------------------------------------------------
local mmb

local function placeMinimapButton()
  local a = math.rad(BuffCheckDB.minimap.angle or 220)
  local r = (Minimap:GetWidth() / 2) + 10
  mmb:ClearAllPoints()
  mmb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function dragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  BuffCheckDB.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
  placeMinimapButton()
end

local function createMinimapButton()
  local b = CreateFrame("Button", "BuffCheckMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local overlay = b:CreateTexture(nil, "OVERLAY")
  overlay:SetSize(53, 53)
  overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  overlay:SetPoint("TOPLEFT")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", 7, -6)

  b:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", dragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
  end)
  b:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      ns.setMoving(not ns.isMoving())
      refreshAll()
    else
      ns.ToggleOptions()
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("BuffCheck")
    GameTooltip:AddLine(L["Linksklick: Einstellungen"], 1, 1, 1)
    GameTooltip:AddLine(L["Rechtsklick: Icons verschieben an/aus"], 1, 1, 1)
    GameTooltip:AddLine(L["Ziehen: Button verschieben"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

function ns.UpdateMinimapButton()
  if not Minimap then return end
  mmb = mmb or createMinimapButton()
  placeMinimapButton()
  mmb:SetShown(BuffCheckDB.minimap.show)
end

function ns.OnLoad()
  register()
  ns.UpdateMinimapButton()
end
