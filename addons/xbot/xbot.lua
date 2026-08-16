-- XBot - kleine Steuerzentrale fuer die .x-Befehle von Nostalgia

XBotDB = XBotDB or {}

local PANEL_WIDTH = 320
local PANEL_HEIGHT = 180

local function SendCommand(command)
    -- Den Befehl ueber das normale Chatfenster senden, damit er wie ein
    -- manuell geschriebener .x-Befehl beim Server ankommt.
    if ChatFrameEditBox then
        ChatFrameEditBox:SetText(command)
        ChatEdit_SendText(ChatFrameEditBox)
    else
        SendChatMessage(command, "SAY")
    end
end

local frame = CreateFrame("Frame", "XBotFrame", UIParent)
frame:SetWidth(PANEL_WIDTH)
frame:SetHeight(PANEL_HEIGHT)
frame:SetFrameStrata("DIALOG")

if XBotDB.x and XBotDB.y then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", XBotDB.x, XBotDB.y)
else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
end

frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})
frame:SetBackdropColor(0.025, 0.035, 0.08, 0.96)
frame:SetBackdropBorderColor(0.72, 0.55, 0.16, 1)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function()
    this:StartMoving()
end)
frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local _, _, _, x, y = this:GetPoint()
    XBotDB.x = x
    XBotDB.y = y
end)
frame:Hide()

local header = frame:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\Buttons\\WHITE8x8")
header:SetVertexColor(0.10, 0.17, 0.32, 0.95)
header:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
header:SetHeight(30)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, -13)
title:SetText("|cffd8ad43NOSTALGIA|r  |cff9ecbffXBot|r")

local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
subtitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -17, -17)
subtitle:SetText("Bots")
subtitle:SetTextColor(0.68, 0.76, 0.92)

local function AddTooltip(button, text)
    button:SetScript("OnEnter", function()
        this.background:SetVertexColor(this.hoverR, this.hoverG, this.hoverB, 1)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(this.tooltip, 1, 0.82, 0.25, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        this.background:SetVertexColor(this.baseR, this.baseG, this.baseB, 0.96)
        GameTooltip:Hide()
    end)
    button.tooltip = text
end

local function CreateButton(label, tooltip, command, width, x, y, r, g, b)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(26)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    button:SetText(label)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Buttons\\WHITE8x8")
    background:SetAllPoints(button)
    background:SetVertexColor(r, g, b, 0.96)
    button.background = background
    button.baseR = r
    button.baseG = g
    button.baseB = b
    button.hoverR = r + (1 - r) * 0.26
    button.hoverG = g + (1 - g) * 0.26
    button.hoverB = b + (1 - b) * 0.26

    AddTooltip(button, tooltip)
    if type(command) == "function" then
        button:SetScript("OnClick", command)
    else
        button:SetScript("OnClick", function()
            SendCommand(command)
        end)
    end
    return button
end

-- Reihe 1: sofortige Kampfsteuerung
CreateButton("ANGREIFEN", "Alle Bots greifen dein aktuelles Ziel an.  (.x attack)", ".x attack", 296, 12, -44, 0.52, 0.10, 0.10)

-- Reihe 2: Rollen und Flaechenschaden
CreateButton("TANK", "Fuegt einen Tank-Bot hinzu.  (.x tank)", ".x tank", 68, 12, -74, 0.19, 0.30, 0.58)
CreateButton("HEILER", "Fuegt einen Heiler-Bot hinzu.  (.x heal)", ".x heal", 68, 84, -74, 0.20, 0.48, 0.28)
CreateButton("DPS", "Fuegt einen DPS-Bot hinzu.  (.x dps)", ".x dps", 68, 156, -74, 0.52, 0.29, 0.10)
CreateButton("FLAECHE", "Bots benutzen ihre Flaechenfaehigkeiten.  (.x aoe)", ".x aoe", 68, 228, -74, 0.34, 0.18, 0.55)

local followToggle = false
local followButton
local function ToggleFollow()
    if followToggle then
        SendCommand(".x summon")
        followButton:SetText("FOLGEN")
        followButton.tooltip = "Bots laufen zu dir.  (.x follow)"
    else
        SendCommand(".x follow")
        followButton:SetText("HERHOLEN")
        followButton.tooltip = "Bots sofort zu dir holen.  (.x summon)"
    end
    followToggle = not followToggle
end
followButton = CreateButton("FOLGEN", "Bots laufen zu dir.  (.x follow)", ToggleFollow, 68, 12, -104, 0.15, 0.37, 0.52)

local pauseToggle = false
local pauseButton
local function TogglePause()
    if pauseToggle then
        SendCommand(".x unpause")
        pauseButton:SetText("PAUSE")
        pauseButton.tooltip = "Bots halten ihre aktuelle Aktion an.  (.x pause)"
    else
        SendCommand(".x pause")
        pauseButton:SetText("WEITER")
        pauseButton.tooltip = "Bots setzen ihre Aktion fort.  (.x unpause)"
    end
    pauseToggle = not pauseToggle
end
pauseButton = CreateButton("PAUSE", "Bots halten ihre aktuelle Aktion an.  (.x pause)", TogglePause, 68, 84, -104, 0.34, 0.34, 0.16)

CreateButton("BELEBEN", "Bots beleben gefallene Gruppenmitglieder.  (.x rezz)", ".x rezz", 68, 156, -104, 0.23, 0.42, 0.26)

local ccMarks = {
    { icon = 1, label = "Stern", command = "star" },
    { icon = 2, label = "Kreis", command = "circle" },
    { icon = 3, label = "Diamant", command = "diamond" },
    { icon = 4, label = "Dreieck", command = "triangle" },
    { icon = 5, label = "Mond", command = "moon" },
    { icon = 6, label = "Quadrat", command = "square" },
    { icon = 7, label = "Kreuz", command = "cross" },
    { icon = 8, label = "Totenkopf", command = "skull" }
}
local ccIndex = 1
local ccButton
local function MarkCrowdControl()
    if not UnitExists("target") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040XBot: Kein Ziel ausgewaehlt.|r")
        return
    end

    local mark = ccMarks[ccIndex]
    SetRaidTarget("target", mark.icon)
    SendCommand(".x ccmark " .. mark.command)
    ccIndex = ccIndex + 1
    if ccIndex > table.getn(ccMarks) then
        ccIndex = 1
    end
    ccButton:SetText("CC: " .. ccMarks[ccIndex].label)
    ccButton.tooltip = "Markiert das Ziel fuer Crowd Control. Naechste Marke: " .. ccMarks[ccIndex].label .. "."
end
ccButton = CreateButton("CC: Stern", "Markiert das Ziel fuer Crowd Control. Naechste Marke: Stern.", MarkCrowdControl, 68, 228, -104, 0.31, 0.18, 0.50)

local function UseButton()
    if UnitExists("target") then
        TargetUnit("target")
    end
    SendCommand(".x use")
end
CreateButton("BENUTZEN", "Bots benutzen ihr Ziel bzw. einen Gegenstand.  (.x use)", UseButton, 68, 12, -134, 0.27, 0.30, 0.36)
CreateButton("MORDE", "Fuehrt den Morde-Befehl aus.  (.x morde)", ".x morde", 68, 84, -134, 0.42, 0.16, 0.22)
CreateButton("XP", "Fuehrt den XP-Befehl aus.  (.x xp)", ".x xp", 68, 156, -134, 0.17, 0.39, 0.34)
CreateButton("ZU", "Schliesst dieses Fenster.  (/xbot oeffnet es wieder)", function()
    frame:Hide()
end, 68, 228, -134, 0.23, 0.23, 0.27)

local footer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
footer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 7)
footer:SetText("/xbot  |  Zum Verschieben ziehen")
footer:SetTextColor(0.57, 0.66, 0.82)

local function ToggleWindow()
    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Verschiebbarer Zugang am Minimap-Rand.  Der Winkel wird in XBotDB
-- gespeichert, damit die Schaltflaeche beim naechsten Einloggen an derselben
-- Stelle sitzt.
local minimapButton = CreateFrame("Button", "XBotMinimapButton", Minimap)
minimapButton:SetWidth(24)
minimapButton:SetHeight(24)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:EnableMouse(true)
minimapButton:RegisterForDrag("LeftButton")
local minimapBackground = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapBackground:SetTexture("Interface\\Buttons\\WHITE8x8")
minimapBackground:SetAllPoints(minimapButton)
minimapBackground:SetVertexColor(0.03, 0.10, 0.30, 0.96)

local minimapMark = minimapButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
minimapMark:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
minimapMark:SetText("X")
minimapMark:SetTextColor(0.34, 0.76, 1.0)

local function UpdateMinimapPosition()
    local angle = XBotDB.minimapAngle or 2.35
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
end

minimapButton:SetScript("OnEnter", function()
    minimapBackground:SetVertexColor(0.06, 0.19, 0.48, 1)
    minimapMark:SetTextColor(0.64, 0.90, 1.0)
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("|cffd8ad43Nostalgia XBot|r", 1, 0.82, 0.25)
    GameTooltip:AddLine("Linksklick: Partybot-Steuerung oeffnen", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Ziehen: Position veraendern", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function()
    minimapBackground:SetVertexColor(0.03, 0.10, 0.30, 0.96)
    minimapMark:SetTextColor(0.34, 0.76, 1.0)
    GameTooltip:Hide()
end)
minimapButton:SetScript("OnDragStart", function()
    this.dragged = false
    this:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        local centerX, centerY = Minimap:GetCenter()
        if centerX and centerY then
            XBotDB.minimapAngle = math.atan2(cursorY / scale - centerY, cursorX / scale - centerX)
            UpdateMinimapPosition()
            this.dragged = true
        end
    end)
end)
minimapButton:SetScript("OnDragStop", function()
    this:SetScript("OnUpdate", nil)
    this.movedAt = GetTime()
end)
minimapButton:SetScript("OnClick", function()
    if not this.movedAt or GetTime() - this.movedAt > 0.20 then
        ToggleWindow()
    end
end)
UpdateMinimapPosition()

SLASH_XBOT1 = "/xbot"
SlashCmdList["XBOT"] = function(message)
    if message and string.lower(message) == "reset" then
        XBotDB.x = nil
        XBotDB.y = nil
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -40)
        frame:Show()
        return
    end

    ToggleWindow()
end

frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function()
    local _, _, _, x, y = frame:GetPoint()
    XBotDB.x = x
    XBotDB.y = y
end)
