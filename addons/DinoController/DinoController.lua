-- DinoController - WoW-seitige Komfortfunktionen fuer Vanilla 1.12.1.
-- XInput, Cursor-Automatik und Tastatur/Maus-Ausgabe bleiben in der Bridge.

DinoControllerDB = DinoControllerDB or {}
DinoControllerBridgeConfig = DinoControllerBridgeConfig or { Enabled = 1, ButtonMappings = {} }

local BINDING_VERSION = 8
local CAMERA_PITCH = 20
local autoLootCVarAvailable = nil
local ambiguousQuestList = nil
local ambiguityClearAt = nil

local lootStatePixel = CreateFrame("Frame", "DinoLootStatePixel", UIParent)
lootStatePixel:SetWidth(10)
lootStatePixel:SetHeight(10)
lootStatePixel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
lootStatePixel:SetFrameStrata("TOOLTIP")
lootStatePixel.tex = lootStatePixel:CreateTexture(nil, "OVERLAY")
lootStatePixel.tex:SetAllPoints()
lootStatePixel.tex:SetTexture(0, 1, 1, 1) -- Cyan: NUMPAD0 ist Confirm
lootStatePixel:Hide()
local uiModeActive = nil

local controllerBindings = {
    { "NUMPAD8", "MOVEFORWARD" },
    { "NUMPAD2", "MOVEBACKWARD" },
    { "NUMPAD4", "STRAFELEFT" },
    { "NUMPAD6", "STRAFERIGHT" },
    { "NUMPAD5", "TOGGLEWORLDMAP" },
    { "NUMPAD7", "TOGGLEAUTORUN" },
    { "F8", "DINOCONTROLLER_MENU_CYCLE" },
    { "F11", "DINOCONTROLLER_UI_ACTIVATE" }
}

local function EnsureDefaults()
    if DinoControllerDB.controllerEnabled == nil then DinoControllerDB.controllerEnabled = 1 end
    if DinoControllerDB.showReticle == nil then DinoControllerDB.showReticle = 1 end
    if DinoControllerDB.uiEnabled == nil then DinoControllerDB.uiEnabled = 1 end
    if DinoControllerDB.autoQuest == nil then DinoControllerDB.autoQuest = 1 end
    if DinoControllerDB.autoLoot == nil then DinoControllerDB.autoLoot = 1 end
    if DinoControllerDB.swapAB == nil then DinoControllerDB.swapAB = 0 end
    if DinoControllerDB.swapXY == nil then DinoControllerDB.swapXY = 0 end
    if DinoControllerDB.menuAction == nil then DinoControllerDB.menuAction = 1 end
    if DinoControllerDB.xActionType == nil then DinoControllerDB.xActionType = "ClassMode" end
    if DinoControllerDB.targetMode ~= "healer" then DinoControllerDB.targetMode = "dps" end

end

EnsureDefaults()

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fc8ffDinoController:|r " .. message)
    end
end

local function OnOff(value)
    if value == 1 then return "AN" end
    return "AUS"
end

local function SafeSetCVar(name, value)
    return pcall(SetCVar, name, value)
end

function DinoController_NormalizeBindingKey(key)
    if not key then return nil end
    key = string.upper(key)
    if key == "" or key == "NONE" then return nil end
    key = string.gsub(key, "%+", "-")
    if key == "ESC" then key = "ESCAPE" end
    if key == "RETURN" then key = "ENTER" end
    return key
end

function DinoController_ToggleMenuWindows()
    ToggleCharacter("PaperDollFrame")
    ToggleBackpack()
    local i
    for i = 1, NUM_BAG_SLOTS do
        ToggleBag(i)
    end
end

local function SetActionBinding(key, action)
    if action and action ~= "" then SetBinding(key, action) else SetBinding(key) end
end

local function GetFriendlyTargetUnits()
    local units = {}
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    local index

    if raidCount > 0 then
        -- Im Raid ist der Spieler bereits genau einmal als raidN enthalten.
        for index = 1, raidCount do
            local unit = "raid" .. index
            if UnitExists(unit) then
                table.insert(units, unit)
            end
        end
    else
        table.insert(units, "player")
        for index = 1, partyCount do
            local unit = "party" .. index
            if UnitExists(unit) then
                table.insert(units, unit)
            end
        end
    end

    return units
end

function DinoController_TargetGroup(direction)
    if DinoControllerDB.targetMode ~= "healer" then return end

    local units = GetFriendlyTargetUnits()
    local count = table.getn(units)
    if count == 0 then return end

    local currentIndex = nil
    local index
    for index = 1, count do
        if UnitIsUnit("target", units[index]) then
            currentIndex = index
            break
        end
    end

    local nextIndex
    if currentIndex then
        nextIndex = currentIndex + (direction < 0 and -1 or 1)
        if nextIndex < 1 then nextIndex = count end
        if nextIndex > count then nextIndex = 1 end
    elseif direction < 0 then
        nextIndex = count
    else
        nextIndex = 1
    end

    TargetUnit(units[nextIndex])
end

function DinoController_ApplyTargetMode(save)
    if DinoControllerDB.targetMode == "healer" then
        SetBinding("NUMPAD1", "DINOCONTROLLER_TARGET_GROUP_NEXT")
        SetBinding("NUMPAD3", "DINOCONTROLLER_TARGET_GROUP_PREVIOUS")
    else
        DinoControllerDB.targetMode = "dps"
        SetBinding("NUMPAD1", "TARGETNEARESTENEMY")
        SetBinding("NUMPAD3", "TARGETPREVIOUSENEMY")
    end

    -- Im UI-Modus sind D-Pad und Confirm nur temporaer umgebunden. Diese
    -- Belegung darf beim Wechsel im /dino-Menue nicht dauerhaft gespeichert
    -- werden; beim Verlassen des UI-Modus wird ohnehin sauber gespeichert.
    if save and not uiModeActive then SaveBindings(GetCurrentBindingSet()) end
end

function DinoController_ApplyButtonLayout(save)
    if DinoControllerDB.swapAB == 1 then
        SetBinding("NUMPAD0", "JUMP")           -- Bottom button -> Jump
        SetBinding("NUMPAD9", "TURNORACTION")   -- Right button -> Confirm
        lootStatePixel.tex:SetTexture(1, 0, 1, 1) -- Magenta: NUMPAD9
    else
        SetBinding("NUMPAD0", "TURNORACTION")   -- Bottom button -> Confirm
        SetBinding("NUMPAD9", "JUMP")           -- Right button -> Jump
        lootStatePixel.tex:SetTexture(0, 1, 1, 1) -- Cyan: NUMPAD0
    end

    local mappings = DinoControllerBridgeConfig.ButtonMappings or {}
    local northAction = "TARGETSELF"

    if DinoControllerDB.swapXY == 1 then
        SetActionBinding("NUMPADMINUS", northAction)
        SetActionBinding("NUMPADPLUS", "DINOCONTROLLER_X_ACTION")
    else
        SetActionBinding("NUMPADMINUS", "DINOCONTROLLER_X_ACTION")
        SetActionBinding("NUMPADPLUS", northAction)
    end

    if LootFrame and LootFrame:IsVisible() and DinoController_IsUIModeActive and DinoController_IsUIModeActive() then
        lootStatePixel:Show()
    else
        lootStatePixel:Hide()
    end

    if save then SaveBindings(GetCurrentBindingSet()) end
end

function DinoController_ExecuteXAction()
    local actionType = DinoControllerDB.xActionType
    if actionType == "Action" then
        local slot = 13
        if type(slot) == "number" then
            UseAction(slot)
        end
    else
        if DinoHUD_CycleClassStance then
            DinoHUD_CycleClassStance()
        end
    end
end

function DinoController_ExecuteYAction()
    TargetUnit("player")
end

local function ApplyCamera()
    SafeSetCVar("cameraDistanceMaxFactor", "2")
    SafeSetCVar("cameraYawMoveSpeed", "180")
    SafeSetCVar("cameraPitchMoveSpeed", "90")
    SafeSetCVar("cameraSmoothStyle", "0")
    SafeSetCVar("cameraSmoothTrackingStyle", "0")
    SafeSetCVar("cameraTerrainTilt", "0")
    SafeSetCVar("cameraBobbing", "0")
    SafeSetCVar("cameraPitch", tostring(CAMERA_PITCH))
    CameraZoomOut(50)
end

local function InstallBindings(force)
    if not force and DinoControllerDB.bindingVersion == BINDING_VERSION then
        return
    end

    local index
    for index = 1, table.getn(controllerBindings) do
        local binding = controllerBindings[index]
        SetBinding(binding[1], binding[2])
    end

    DinoController_ApplyTargetMode(nil)
    DinoController_ApplyButtonLayout(nil)

    if DinoHUD_InstallWorldBindings then
        DinoHUD_InstallWorldBindings()
    end

    SaveBindings(GetCurrentBindingSet())
    DinoControllerDB.bindingVersion = BINDING_VERSION
    Print("Controller-Tastenbelegung wurde installiert.")
end

local reticle = CreateFrame("Frame", "DinoControllerReticle", UIParent)
reticle:SetWidth(14)
reticle:SetHeight(14)
reticle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
reticle:SetFrameStrata("TOOLTIP")

local horizontal = reticle:CreateTexture(nil, "OVERLAY")
horizontal:SetTexture("Interface\\Buttons\\WHITE8x8")
horizontal:SetVertexColor(0.55, 0.86, 1.0, 0.75)
horizontal:SetWidth(14)
horizontal:SetHeight(2)
horizontal:SetPoint("CENTER", reticle, "CENTER", 0, 0)

local vertical = reticle:CreateTexture(nil, "OVERLAY")
vertical:SetTexture("Interface\\Buttons\\WHITE8x8")
vertical:SetVertexColor(0.55, 0.86, 1.0, 0.75)
vertical:SetWidth(2)
vertical:SetHeight(14)
vertical:SetPoint("CENTER", reticle, "CENTER", 0, 0)

local function UpdateReticle()
    if DinoControllerDB.controllerEnabled == 1 and DinoControllerDB.showReticle == 1 and not uiModeActive then
        reticle:Show()
    else
        reticle:Hide()
    end
end

function DinoController_SetUIMode(active)
    uiModeActive = active
    UpdateReticle()
end

local function DetectAutoLootCVar()
    local ok, value = pcall(GetCVar, "autoLootDefault")
    autoLootCVarAvailable = ok and value and value ~= ""
end

local function ApplyAutoLootSetting()
    if autoLootCVarAvailable == nil then DetectAutoLootCVar() end
    if autoLootCVarAvailable then
        SafeSetCVar("autoLootDefault", DinoControllerDB.autoLoot == 1 and "1" or "0")
    end
end

local function LootAllSafeSlots()
    if DinoControllerDB.autoLoot ~= 1 then return end

    local slot
    for slot = GetNumLootItems(), 1, -1 do
        if LootSlotIsCoin(slot) or LootSlotIsItem(slot) then
            LootSlot(slot)
        end
    end
end

-- Removed old lootStatePixel declaration location

local function PositionLootFrameAtCursor()
    -- Disabled: Handled dynamically by DinoControllerUI
end

local function MarkQuestListAmbiguous()
    if not ambiguousQuestList then
        Print("Mehrere Quests vorhanden - bitte eine Quest auswaehlen.")
    end
    ambiguousQuestList = 1
end

local function CancelAmbiguityClear()
    ambiguityClearAt = nil
end

local function HandleQuestGreeting()
    CancelAmbiguityClear()
    if DinoControllerDB.autoQuest ~= 1 then return end
    local active = GetNumActiveQuests() or 0
    local available = GetNumAvailableQuests() or 0
    if active + available > 1 then
        MarkQuestListAmbiguous()
    elseif active + available == 1 and not ambiguousQuestList then
        if active == 1 then SelectActiveQuest(1) else SelectAvailableQuest(1) end
    end
end

local function HandleGossipShow()
    CancelAmbiguityClear()
    if DinoControllerDB.autoQuest ~= 1 then return end
    local activeValues = { GetGossipActiveQuests() }
    local availableValues = { GetGossipAvailableQuests() }
    local active = table.getn(activeValues) / 2
    local available = table.getn(availableValues) / 2
    if active + available > 1 then
        MarkQuestListAmbiguous()
    elseif active + available == 1 and not ambiguousQuestList then
        if active == 1 then SelectGossipActiveQuest(1) else SelectGossipAvailableQuest(1) end
    end
end

local function HandleQuestEvent(eventName)
    if eventName == "QUEST_GREETING" then
        HandleQuestGreeting()
    elseif eventName == "GOSSIP_SHOW" then
        HandleGossipShow()
    elseif eventName == "QUEST_DETAIL" then
        CancelAmbiguityClear()
        if DinoControllerDB.autoQuest == 1 then AcceptQuest() end
    elseif eventName == "QUEST_PROGRESS" then
        CancelAmbiguityClear()
        if DinoControllerDB.autoQuest == 1 and IsQuestCompletable() then CompleteQuest() end
    elseif eventName == "QUEST_COMPLETE" then
        CancelAmbiguityClear()
        local choices = GetNumQuestChoices()
        if choices > 1 then
            Print("Mehrere Belohnungen - mit D-Pad waehlen und mit Confirm bestaetigen.")
        elseif DinoControllerDB.autoQuest == 1 then
            if choices == 1 then GetQuestReward(1) else GetQuestReward(0) end
        end
    elseif eventName == "QUEST_FINISHED" or eventName == "GOSSIP_CLOSED" then
        ambiguityClearAt = GetTime() + 5
    end
end

function DinoController_SetControllerEnabled(enabled)
    local state = enabled and 1 or 0
    DinoControllerDB.controllerEnabled = state
    if state == 1 then
        InstallBindings(true)
        if DinoHUD_UpdateVisibility then DinoHUD_UpdateVisibility() end
        UpdateReticle()
        Print("Controller-Unterstuetzung: |cff55ff77AKTIV|r")
    else
        if DinoController_LeaveUIMode then DinoController_LeaveUIMode() end
        if DinoHUD_UpdateVisibility then DinoHUD_UpdateVisibility() end
        UpdateReticle()
        Print("Controller-Unterstuetzung: |cffff5555INAKTIV|r")
    end
    if UpdateMenu then UpdateMenu() end
end

local menu = CreateFrame("Frame", "DinoControllerMenu", UIParent)
menu:SetWidth(380)
menu:SetHeight(380)
menu:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
menu:SetFrameStrata("DIALOG")
menu:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})
menu:SetBackdropColor(0.02, 0.04, 0.08, 0.97)
menu:SetBackdropBorderColor(0.34, 0.67, 0.92, 1)
menu:EnableMouse(true)
menu:SetMovable(true)
menu:RegisterForDrag("LeftButton")
menu:SetScript("OnDragStart", function() this:StartMoving() end)
menu:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
menu:Hide()

local menuTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
menuTitle:SetPoint("TOPLEFT", menu, "TOPLEFT", 18, -16)
menuTitle:SetText("DinoController")

local function CreateMenuButton(y, width, callback)
    local button = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    button:SetWidth(width or 210)
    button:SetHeight(25)
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 18, y)
    button:SetScript("OnClick", callback)
    return button
end

local controllerButton
local reticleButton
local autoQuestButton
local autoLootButton
local hudButton
local hudLockButton
local swapABButton
local swapXYButton
local targetDpsButton
local targetHealerButton
local menuActionButton
local l3SlotText
local xActionTypeText
local xActionSlotText

local function UpdateMenu()
    EnsureDefaults()
    controllerButton:SetText("Controller-Unterstuetzung: " .. OnOff(DinoControllerDB.controllerEnabled))
    reticleButton:SetText("Fadenkreuz: " .. OnOff(DinoControllerDB.showReticle))
    autoQuestButton:SetText("Auto Quest: " .. OnOff(DinoControllerDB.autoQuest))
    hudButton:SetText("Controller-HUD: " .. OnOff(DinoControllerHUDDB and DinoControllerHUDDB.hudVisible or 1))
    hudLockButton:SetText("HUD Position: " .. ((DinoControllerHUDDB and DinoControllerHUDDB.hudLocked == 1) and "Gesperrt" or "Entsperrt"))
    swapABButton:SetText("A und B tauschen: " .. OnOff(DinoControllerDB.swapAB))
    swapXYButton:SetText("X und Y tauschen: " .. OnOff(DinoControllerDB.swapXY))
    targetDpsButton:SetText(DinoControllerDB.targetMode == "dps" and "[ DPS/Tank ]" or "DPS/Tank")
    targetHealerButton:SetText(DinoControllerDB.targetMode == "healer" and "[ Healer ]" or "Healer")

    if xActionTypeText then
        local actionType = DinoControllerDB.xActionType or "ClassMode"
        xActionTypeText:SetText("Aktion: " .. actionType)
    end
end

controllerButton = CreateMenuButton(-48, 220, function()
    DinoController_SetControllerEnabled(DinoControllerDB.controllerEnabled ~= 1)
end)

reticleButton = CreateMenuButton(-78, 220, function()
    DinoControllerDB.showReticle = DinoControllerDB.showReticle == 1 and 0 or 1
    UpdateReticle()
    UpdateMenu()
end)

autoQuestButton = CreateMenuButton(-108, 220, function()
    DinoControllerDB.autoQuest = DinoControllerDB.autoQuest == 1 and 0 or 1
    UpdateMenu()
end)

hudButton = CreateMenuButton(-138, 220, function()
    if DinoControllerHUDDB then
        if DinoControllerHUDDB.hudVisible == 1 then
            if DinoHUD_Hide then DinoHUD_Hide() end
        else
            if DinoHUD_Show then DinoHUD_Show() end
        end
    end
    UpdateMenu()
end)

hudLockButton = CreateMenuButton(-168, 220, function()
    if DinoControllerHUDDB then
        if DinoControllerHUDDB.hudLocked == 1 then
            if DinoHUD_Unlock then DinoHUD_Unlock() end
        else
            if DinoHUD_Lock then DinoHUD_Lock() end
        end
    end
    UpdateMenu()
end)

swapABButton = CreateMenuButton(-198, 220, function()
    DinoControllerDB.swapAB = DinoControllerDB.swapAB == 1 and 0 or 1
    DinoController_ApplyButtonLayout(true)
    if DinoController_IsUIModeActive and DinoController_IsUIModeActive() then
        if DinoController_LeaveUIMode then DinoController_LeaveUIMode() end
    end
    UpdateMenu()
    if DinoHUD_UpdateLabels then DinoHUD_UpdateLabels() end
end)

swapXYButton = CreateMenuButton(-228, 220, function()
    DinoControllerDB.swapXY = DinoControllerDB.swapXY == 1 and 0 or 1
    DinoController_ApplyButtonLayout(true)
    UpdateMenu()
    if DinoHUD_UpdateLabels then DinoHUD_UpdateLabels() end
end)

-- X Aktion Section
local xTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
xTitle:SetPoint("TOPLEFT", menu, "TOPLEFT", 250, -48)
xTitle:SetText("X Aktion")

xActionTypeText = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
xActionTypeText:SetPoint("TOPLEFT", menu, "TOPLEFT", 250, -72)

local xActionTypeToggle = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
xActionTypeToggle:SetWidth(120); xActionTypeToggle:SetHeight(22)
xActionTypeToggle:SetPoint("TOPLEFT", menu, "TOPLEFT", 250, -94)
xActionTypeToggle:SetText("Modus wechseln")
xActionTypeToggle:SetScript("OnClick", function()
    local t = DinoControllerDB.xActionType or "ClassMode"
    if t == "ClassMode" then
        DinoControllerDB.xActionType = "Action"
    else
        DinoControllerDB.xActionType = "ClassMode"
    end
    UpdateMenu()
    if DinoHUD_UpdateLabels then DinoHUD_UpdateLabels() end
    if UpdateAllButtons then UpdateAllButtons() end
end)

local targetModeTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetModeTitle:SetPoint("TOPLEFT", menu, "TOPLEFT", 250, -138)
targetModeTitle:SetText("Target-Modus")

targetDpsButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
targetDpsButton:SetWidth(112)
targetDpsButton:SetHeight(22)
targetDpsButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 250, -158)
targetDpsButton:SetScript("OnClick", function()
    DinoControllerDB.targetMode = "dps"
    DinoController_ApplyTargetMode(true)
    UpdateMenu()
    Print("Target-Modus: DPS/Tank.")
end)

targetHealerButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
targetHealerButton:SetWidth(112)
targetHealerButton:SetHeight(22)
targetHealerButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 250, -184)
targetHealerButton:SetScript("OnClick", function()
    DinoControllerDB.targetMode = "healer"
    DinoController_ApplyTargetMode(true)
    UpdateMenu()
    Print("Target-Modus: Healer.")
end)

local infoText = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
infoText:SetPoint("TOPLEFT", menu, "TOPLEFT", 18, -260)
infoText:SetJustifyH("LEFT")
infoText:SetText("|cff33ff99Info:|r\n" ..
                 "Aktionsleiste 2\n" ..
                 "Slot 13 und Slot 14 belegen\n\n" ..
                 "sowie 1-12 Leiste 1 belegen\n" ..
                 "fuer D-pad, L2 D-pad, R2 D-pad\n\n" ..
                 "|cffffff77/dino bind|r - Controller Tasten neu installieren")

local closeButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
closeButton:SetWidth(90)
closeButton:SetHeight(25)
closeButton:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -18, 16)
closeButton:SetText("Schliessen")
closeButton:SetScript("OnClick", function() menu:Hide() end)

local function ToggleMenu()
    if menu:IsVisible() then menu:Hide() else UpdateMenu(); menu:Show() end
end

local function SetOption(name, value)
    local enabled
    if value == "on" or value == "an" or value == "1" then enabled = 1 end
    if value == "off" or value == "aus" or value == "0" then enabled = 0 end
    if enabled == nil then
        Print("Bitte 'on' oder 'off' angeben.")
        return
    end

    DinoControllerDB[name] = enabled
    if name == "showReticle" then UpdateReticle() end
    if name == "autoLoot" then ApplyAutoLootSetting() end
    UpdateMenu()
end

local function PrintStatus()
    Print("Controller " .. OnOff(DinoControllerDB.controllerEnabled) ..
        ", Fadenkreuz " .. OnOff(DinoControllerDB.showReticle) ..
        ", UI " .. OnOff(DinoControllerDB.uiEnabled) ..
        ", AutoQuest " .. OnOff(DinoControllerDB.autoQuest) ..
        ", AutoLoot " .. OnOff(DinoControllerDB.autoLoot) ..
        ", Target " .. (DinoControllerDB.targetMode == "healer" and "Healer" or "DPS/Tank") ..
        ", L3 Slot " .. (DinoControllerDB.l3Slot or 1) .. ".")
end

SLASH_DINOCONTROLLER1 = "/dino"
SlashCmdList["DINOCONTROLLER"] = function(message)
    local text = string.lower(message or "")
    local _, _, command, value = string.find(text, "^(%S*)%s*(%S*)")
    if command == "" or command == "menu" then
        ToggleMenu()
    elseif command == "camera" then
        ApplyCamera()
        Print("Kameraeinstellungen wurden erneut angewendet.")
    elseif command == "bind" or command == "bindings" then
        InstallBindings(true)
    elseif command == "reticle" or command == "fadenkreuz" then
        if value == "" then
            DinoControllerDB.showReticle = DinoControllerDB.showReticle == 1 and 0 or 1
            UpdateReticle()
            UpdateMenu()
        else
            SetOption("showReticle", value)
        end
        Print("Fadenkreuz " .. OnOff(DinoControllerDB.showReticle) .. ".")
    elseif command == "ui" then
        if value == "" then
            DinoControllerDB.uiEnabled = DinoControllerDB.uiEnabled == 1 and 0 or 1
        else
            SetOption("uiEnabled", value)
        end
        if DinoControllerDB.uiEnabled == 0 and DinoController_LeaveUIMode then
            DinoController_LeaveUIMode()
        end
        Print("Controller-UI " .. OnOff(DinoControllerDB.uiEnabled) .. ".")
    elseif command == "autoquest" then
        SetOption("autoQuest", value)
        Print("Auto Quest " .. OnOff(DinoControllerDB.autoQuest) .. ".")
    elseif command == "autoloot" then
        SetOption("autoLoot", value)
        Print("Auto Loot " .. OnOff(DinoControllerDB.autoLoot) .. ".")
    elseif command == "layout" then
        if value == "xbox" or value == "nintendo" then
            DinoControllerDB.buttonLayout = value
            DinoControllerDB.swapAB = value == "nintendo" and 1 or 0
            DinoControllerDB.layoutMappingVersion = 2
            if not uiModeActive then DinoController_ApplyButtonLayout(1) end
            UpdateMenu()
            Print("Button Layout: " .. (value == "nintendo" and "Nintendo" or "Xbox") .. ".")
        else
            Print("Bitte '/dino layout xbox' oder '/dino layout nintendo' verwenden.")
        end
    elseif command == "target" or command == "targetmode" then
        if value == "healer" or value == "heal" then
            DinoControllerDB.targetMode = "healer"
            DinoController_ApplyTargetMode(true)
            UpdateMenu()
            Print("Target-Modus: Healer.")
        elseif value == "dps" or value == "tank" or value == "dpstank" then
            DinoControllerDB.targetMode = "dps"
            DinoController_ApplyTargetMode(true)
            UpdateMenu()
            Print("Target-Modus: DPS/Tank.")
        else
            Print("Bitte '/dino target dps' oder '/dino target healer' verwenden.")
        end
    elseif command == "controller" then
        if value == "on" or value == "an" or value == "1" then
            DinoController_SetControllerEnabled(true)
        elseif value == "off" or value == "aus" or value == "0" then
            DinoController_SetControllerEnabled(false)
        else
            DinoController_SetControllerEnabled(DinoControllerDB.controllerEnabled ~= 1)
        end
    elseif command == "status" then
        PrintStatus()
    else
        Print("/dino | controller on/off | target dps/healer | reticle on/off | ui on/off | autoquest on/off | autoloot on/off | status")
        Print("/dino lock | unlock | hud on/off")
    end
end

local frame = CreateFrame("Frame", "DinoControllerEventFrame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("QUEST_GREETING")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_FINISHED")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("GOSSIP_CLOSED")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
frame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00DinoController: /dino oeffnet das Einstellungsmenue|r")
        end
        InstallBindings(false)
        -- Den gespeicherten A/B-Schalter bei jedem Login erneut anwenden,
        -- auch wenn sich die Binding-Version nicht geaendert hat.
        DinoController_ApplyButtonLayout(nil)
        DinoController_ApplyTargetMode(nil)
        if DinoHUD_InstallWorldBindings then DinoHUD_InstallWorldBindings() end
        SaveBindings(GetCurrentBindingSet())
        DetectAutoLootCVar()
        ApplyAutoLootSetting()
        UpdateReticle()
        this.pendingCamera = 1
    elseif event == "LOOT_OPENED" then
        PositionLootFrameAtCursor()
    elseif event == "UPDATE_BONUS_ACTIONBAR" then
        if DinoControllerDB and DinoControllerDB.controllerEnabled == 1 then
            if BonusActionBarFrame and BonusActionBarFrame:IsVisible() then
                BonusActionBarFrame:Hide()
            end
        end
    else
        HandleQuestEvent(event)
    end
end)
frame:SetScript("OnUpdate", function()
    if this.pendingCamera then
        this.pendingCamera = this.pendingCamera - 1
        if this.pendingCamera <= 0 then
            ApplyCamera()
            this.pendingCamera = nil
        end
    end

    if LootFrame and LootFrame:IsVisible() and DinoController_IsUIModeActive and DinoController_IsUIModeActive() then
        lootStatePixel:Show()
    else
        lootStatePixel:Hide()
    end

    if ambiguityClearAt and GetTime() >= ambiguityClearAt then
        ambiguousQuestList = nil
        ambiguityClearAt = nil
    end
end)

local original_ShowBonusActionBar = ShowBonusActionBar
if original_ShowBonusActionBar then
    function ShowBonusActionBar()
        if DinoControllerDB and DinoControllerDB.controllerEnabled == 1 then
            if BonusActionBarFrame then BonusActionBarFrame:Hide() end
            return
        end
        original_ShowBonusActionBar()
    end
end
