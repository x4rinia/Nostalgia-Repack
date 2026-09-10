-- DinoController - controller convenience features for Vanilla 1.12.1.
-- Author: Nostalgia Team
-- XInput, automatic cursor handling, and keyboard/mouse output remain in the bridge.

DinoControllerDB = DinoControllerDB or {}
DinoControllerCharacterDB = DinoControllerCharacterDB or {}
DinoControllerBridgeConfig = DinoControllerBridgeConfig or { Enabled = 1, ButtonMappings = {} }

local BINDING_VERSION = 15
local CAMERA_PITCH = 20
local RETICLE_ALPHA_LEVELS = { 0.30, 0.50, 0.75 }
local autoLootCVarAvailable = nil
local ambiguousQuestList = nil
local ambiguityClearAt = nil
local pendingQuestWatchSnapshot = nil
local pendingQuestWatchUntil = nil
local nextMapQuestWindow = "map"
local pendingMapQuestWindow = nil

local lootStatePixel = CreateFrame("Frame", "DinoLootStatePixel", UIParent)
lootStatePixel:SetWidth(4)
lootStatePixel:SetHeight(4)
lootStatePixel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
lootStatePixel:SetFrameStrata("TOOLTIP")
lootStatePixel.tex = lootStatePixel:CreateTexture(nil, "OVERLAY")
lootStatePixel.tex:SetAllPoints()
lootStatePixel.tex:SetTexture(0, 0.125, 0.125, 1)
lootStatePixel:Show()
local uiModeActive = nil
local uiModeContext = nil

local function WorldMapIsVisible()
    return WorldMapFrame and WorldMapFrame:IsVisible()
end

local function NPCInteractionAllowsCursor()
    if not uiModeActive then return nil end
    return uiModeContext == "quest" or
        uiModeContext == "gossip" or
        uiModeContext == "trainer" or
        uiModeContext == "bank" or
        uiModeContext == "auction" or
        uiModeContext == "mail" or
        uiModeContext == "stable"
end

local function UpdateControllerStatePixel()
    if WorldMapFrame and WorldMapFrame:IsVisible() then
        if lootStatePixel:GetParent() ~= WorldMapFrame then
            lootStatePixel:SetParent(WorldMapFrame)
            lootStatePixel:SetFrameStrata("TOOLTIP")
            lootStatePixel:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
            lootStatePixel:ClearAllPoints()
            lootStatePixel:SetPoint("TOPLEFT", WorldMapFrame, "TOPLEFT", 0, 0)
        end
    else
        if lootStatePixel:GetParent() ~= UIParent then
            lootStatePixel:SetParent(UIParent)
            lootStatePixel:SetFrameStrata("TOOLTIP")
            lootStatePixel:ClearAllPoints()
            lootStatePixel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        end
    end

    local lootActive = LootFrame and LootFrame:IsVisible() and
        DinoController_IsUIModeActive and DinoController_IsUIModeActive()
    local cursorState = 0.125
    if lootActive then
        cursorState = 1
    elseif NPCInteractionAllowsCursor() then
        cursorState = 0.5
    end

    if DinoControllerDB.swapAB == 1 then
        lootStatePixel.tex:SetTexture(lootActive and 1 or 0.125, 0, cursorState, 1)
    else
        lootStatePixel.tex:SetTexture(0, lootActive and 1 or 0.125, cursorState, 1)
    end
    lootStatePixel:Show()
end

local controllerBindings = {
    { "NUMPAD8", "MOVEFORWARD" },
    { "NUMPAD2", "MOVEBACKWARD" },
    { "NUMPAD4", "STRAFELEFT" },
    { "NUMPAD6", "STRAFERIGHT" },
    { "NUMPAD5", "DINOCONTROLLER_MAP_QUEST_TOGGLE" },
    { "NUMPAD7", "TOGGLEAUTORUN" },
    { "F8", "DINOCONTROLLER_MENU_CYCLE" },
    { "F11", "DINOCONTROLLER_UI_ACTIVATE" }
}

local function EnsureDefaults()
    if DinoControllerDB.controllerEnabled == nil then DinoControllerDB.controllerEnabled = 1 end
    if DinoControllerDB.showReticle == nil then DinoControllerDB.showReticle = 1 end
    if DinoControllerDB.reticleOpacityLevel ~= 1 and DinoControllerDB.reticleOpacityLevel ~= 2 and DinoControllerDB.reticleOpacityLevel ~= 3 then
        DinoControllerDB.reticleOpacityLevel = 3
    end
    if DinoControllerDB.uiEnabled == nil then DinoControllerDB.uiEnabled = 1 end
    if DinoControllerDB.autoQuest == nil then DinoControllerDB.autoQuest = 1 end
    if DinoControllerDB.autoLoot == nil then DinoControllerDB.autoLoot = 1 end
    if DinoControllerDB.swapAB == nil then DinoControllerDB.swapAB = 0 end
    if DinoControllerDB.swapXY == nil then DinoControllerDB.swapXY = 0 end
    if DinoControllerDB.menuAction == nil then DinoControllerDB.menuAction = 1 end
    if DinoControllerDB.targetMode ~= "healer" then DinoControllerDB.targetMode = "dps" end
    if DinoControllerDB.autoTrackQuest == nil then DinoControllerDB.autoTrackQuest = 1 end
    if DinoControllerDB.swapMenuButtons == nil then DinoControllerDB.swapMenuButtons = 0 end
    if DinoControllerDB.secondaryWindows == nil then DinoControllerDB.secondaryWindows = 1 end
    if DinoControllerDB.dpadLayout == nil then DinoControllerDB.dpadLayout = "Standard" end
    -- "Unten", "Mitte", and "Seitlich" are legacy SavedVariable enum values.
    -- They remain internal for compatibility and are mapped to English UI labels.
    if DinoControllerDB.hudLayout == nil then DinoControllerDB.hudLayout = "Unten" end
    if DinoControllerDB.groundSpellMode == nil then
        DinoControllerDB.groundSpellMode = 0
    elseif DinoControllerDB.groundSpellMode ~= 0 then
        -- Migrate old multi-value settings to the new global ON state.
        DinoControllerDB.groundSpellMode = 1
    end
    if DinoControllerCharacterDB.primaryAction == nil then DinoControllerCharacterDB.primaryAction = "Melee" end
end
EnsureDefaults()

function DinoController_GetGroundSpellMode()
    if not DinoControllerDB or DinoControllerDB.groundSpellMode == nil then return 0 end
    return DinoControllerDB.groundSpellMode == 1 and 1 or 0
end

function DinoController_IsAutoGroundSpellEnabled()
    return DinoController_GetGroundSpellMode() == 1
end

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fc8ffDinoController:|r " .. message)
    end
end

local function OnOff(value)
    if value == 1 then return "ON" end
    return "OFF"
end

-- Ground-targeted spells are detected from the 1.12.1 spell data before the
-- original client cast starts, preventing Vanilla's ground-targeting mode.
local originalCastSpell = CastSpell
local originalCastSpellByName = CastSpellByName
local originalUseAction = UseAction
local groundActionTooltip = nil

local function GetPlayerGroundSpellTables()
    local _, classToken = UnitClass("player")
    local keys = DinoGroundSpellKeys and DinoGroundSpellKeys[classToken] or nil
    local names = DinoGroundSpellNames and DinoGroundSpellNames[classToken] or nil
    return keys, names
end

local function GetSpellIdentity(bookIndex, bookType, fallbackName)
    local resolvedBookType = bookType or BOOKTYPE_SPELL or "spell"
    local spellName = fallbackName
    local spellRank = nil
    if bookIndex and GetSpellName then
        spellName, spellRank = GetSpellName(bookIndex, resolvedBookType)
    end

    local spellId = nil
    if bookIndex and GetSpellLink then
        local link = GetSpellLink(bookIndex, resolvedBookType)
        if link then
            local _, _, linkedId = string.find(link, "spell:(%d+)")
            spellId = linkedId and tonumber(linkedId) or nil
        end
    end

    if spellName then
        spellName = string.gsub(spellName, "%s*%b()$", "")
    end

    -- The Vanilla 1.12 client does not reliably provide GetSpellLink on every
    -- casting path. The class/rank table generated from Spell.dbc therefore
    -- supplies the unambiguous numeric spell ID in those cases as well.
    if not spellId and spellName then
        local keys = GetPlayerGroundSpellTables()
        if keys then
            spellId = keys[spellName .. "\031" .. (spellRank or "")]
        end
    end
    return spellId, spellName, spellRank
end

local function FindSpellBookIndex(spellName, wantedRank, wantedTexture)
    if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellName then return nil end
    local bookType = BOOKTYPE_SPELL or "spell"
    local bestIndex = nil
    local tab
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(tab)
        local spellIndex
        for spellIndex = (offset or 0) + 1, (offset or 0) + (count or 0) do
            local name, rank = GetSpellName(spellIndex, bookType)
            local texture = GetSpellTexture and GetSpellTexture(spellIndex, bookType) or nil
            local nameMatches = spellName and name == spellName
            local textureMatches = wantedTexture and texture == wantedTexture
            if nameMatches or (not spellName and textureMatches) then
                bestIndex = spellIndex
                if wantedRank and wantedRank ~= "" and rank == wantedRank then
                    return spellIndex, bookType
                end
            elseif wantedTexture and textureMatches then
                bestIndex = spellIndex
            end
        end
    end
    return bestIndex, bookType
end

local function ResolveActionSpell(actionSlot)
    local actionName, actionRank
    if CreateFrame then
        if not groundActionTooltip then
            groundActionTooltip = CreateFrame("GameTooltip", "DinoGroundSpellScanTooltip", UIParent, "GameTooltipTemplate")
            groundActionTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        end
        groundActionTooltip:ClearLines()
        groundActionTooltip:SetAction(actionSlot)
        local nameLine = getglobal("DinoGroundSpellScanTooltipTextLeft1")
        local rankLine = getglobal("DinoGroundSpellScanTooltipTextRight1")
        actionName = nameLine and nameLine:GetText() or nil
        actionRank = rankLine and rankLine:GetText() or nil
    end
    return FindSpellBookIndex(actionName, actionRank, GetActionTexture and GetActionTexture(actionSlot) or nil)
end

local function ResolveNamedSpell(spellName)
    if not spellName then return nil end
    local baseName = string.gsub(spellName, "%s*%b()$", "")
    local _, _, rank = string.find(spellName, "%((.-)%)%s*$")
    return FindSpellBookIndex(baseName, rank, nil)
end

local function IsGroundSpell(bookIndex, bookType, fallbackName)
    local spellId, spellName = GetSpellIdentity(bookIndex, bookType, fallbackName)
    if spellId and DinoGroundSpellIds and DinoGroundSpellIds[spellId] then
        return 1, spellId, spellName
    end
    local _, names = GetPlayerGroundSpellTables()
    if spellName and names and names[spellName] then
        return 1, spellId, spellName
    end
    return nil, spellId, spellName
end

local function CancelStaleGroundTargeting()
    if SpellIsTargeting and SpellIsTargeting() and SpellStopTargeting then
        SpellStopTargeting()
    end
end

local function ShowAutoGroundError(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
    else
        Print(message)
    end
end

local function TryAutomaticGroundCast(bookIndex, bookType, fallbackName)
    if not DinoController_IsAutoGroundSpellEnabled() then return nil end
    local isGround, spellId, spellName = IsGroundSpell(bookIndex, bookType, fallbackName)
    if not isGround then return nil end

    -- Clear only a state potentially left by an earlier attempt; the current
    -- cast never started the client's targeting mode.
    CancelStaleGroundTargeting()

    -- Deliberately do not fall back when no unit target is selected.
    if not UnitExists or not UnitExists("target") then
        ShowAutoGroundError("This ground-targeted spell requires a target.")
        return "no_target"
    end

    if spellId and SendChatMessage then
        SendChatMessage(".gcast " .. spellId, "SAY")
        return "cast"
    end
    ShowAutoGroundError("The ground-targeted spell ID could not be resolved.")
    return "unresolved"
end

if originalCastSpell then
    function CastSpell(spellIndex, bookType)
        local groundResult = TryAutomaticGroundCast(spellIndex, bookType, nil)
        if groundResult then return nil, groundResult end
        return originalCastSpell(spellIndex, bookType)
    end
end

if originalCastSpellByName then
    function CastSpellByName(spellName, onSelf)
        local bookIndex, bookType = ResolveNamedSpell(spellName)
        local groundResult = TryAutomaticGroundCast(bookIndex, bookType, spellName)
        if groundResult then return nil, groundResult end
        return originalCastSpellByName(spellName, onSelf)
    end
end

if originalUseAction then
    function UseAction(actionSlot, checkCursor, onSelf)
        local bookIndex, bookType = ResolveActionSpell(actionSlot)
        local groundResult = TryAutomaticGroundCast(bookIndex, bookType, nil)
        if groundResult then return nil, groundResult end
        return originalUseAction(actionSlot, checkCursor, onSelf)
    end
end

local primaryActionInfo = {
    Melee = {
        label = "Attack",
        available = 1,
        texture = "Interface\\Icons\\Ability_MeleeDamage"
    }
}

local function GetClassPrimaryAction()
    local _, classToken = UnitClass("player")
    if classToken == "HUNTER" then return "Bow" end
    if classToken == "PRIEST" or classToken == "WARLOCK" or classToken == "MAGE" then return "Wand" end
    return "Melee"
end

-- Localized spell names are internal client-locale lookups and are never shown
-- as English-release labels.
local primarySpellNames = {
    deDE = { Wand = "Schie\195\159en", Bow = "Automatischer Schuss" },
    enUS = { Wand = "Shoot", Bow = "Auto Shot" },
    enGB = { Wand = "Shoot", Bow = "Auto Shot" }
}

local function FindPrimarySpell(mode)
    local localeNames = primarySpellNames[GetLocale and GetLocale() or "enUS"]
    local wantedName = localeNames and localeNames[mode]
    if not wantedName then return nil end

    local wantedTexture = mode == "Wand" and "ability_shootwand" or "ability_whirlwind"
    local bookType = BOOKTYPE_SPELL or "spell"
    local tabCount = GetNumSpellTabs and GetNumSpellTabs() or 0
    local tab
    for tab = 1, tabCount do
        local _, _, offset, spellCount = GetSpellTabInfo(tab)
        local spellIndex
        for spellIndex = (offset or 0) + 1, (offset or 0) + (spellCount or 0) do
            local spellName = GetSpellName(spellIndex, bookType)
            local texture = GetSpellTexture(spellIndex, bookType)
            local normalizedTexture = texture and string.lower(texture) or ""
            if spellName == wantedName and string.find(normalizedTexture, wantedTexture, 1, 1) then
                return spellIndex, spellName, texture
            end
        end
    end
    return nil
end

function DinoController_RefreshPrimaryAction()
    local wandIndex, wandName, wandTexture = FindPrimarySpell("Wand")
    local bowIndex, bowName, bowTexture = FindPrimarySpell("Bow")
    local localeNames = primarySpellNames[GetLocale and GetLocale() or "enUS"] or primarySpellNames.enUS
    primaryActionInfo.Wand = {
        label = "Shoot",
        available = 1,
        spellIndex = wandIndex,
        spellName = wandName or localeNames.Wand,
        texture = wandTexture or "Interface\\Icons\\Ability_ShootWand"
    }
    primaryActionInfo.Bow = {
        label = "Auto Shot",
        available = 1,
        spellIndex = bowIndex,
        spellName = bowName or localeNames.Bow,
        texture = bowTexture or "Interface\\Icons\\Ability_Whirlwind"
    }

    DinoControllerCharacterDB.primaryAction = GetClassPrimaryAction()

    if DinoHUD_RefreshPrimaryAction then DinoHUD_RefreshPrimaryAction() end
end

function DinoController_GetPrimaryActionInfo(mode)
    local selected = mode or DinoControllerCharacterDB.primaryAction or "Melee"
    return primaryActionInfo[selected] or primaryActionInfo.Melee
end

function DinoController_ExecutePrimaryAction(keyState)
    if WorldMapIsVisible() then return end
    if keyState ~= "down" then
        if TurnOrActionStop then TurnOrActionStop() end
        return
    end

    if TurnOrActionStart then TurnOrActionStart() end
    if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then
        return
    end

    local selected = DinoControllerCharacterDB.primaryAction or "Melee"
    local info = primaryActionInfo[selected]
    if not info or info.available ~= 1 then
        DinoController_RefreshPrimaryAction()
        selected = DinoControllerCharacterDB.primaryAction or "Melee"
        info = primaryActionInfo[selected]
    end

    if selected == "Melee" then
        AttackTarget()
    elseif info and info.spellIndex then
        CastSpell(info.spellIndex, BOOKTYPE_SPELL or "spell")
    end
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
    if TalentFrame and TalentFrame:IsVisible() then
        CloseAllBags()
        if HideUIPanel then
            HideUIPanel(TalentFrame)
        else
            TalentFrame:Hide()
        end
        return
    end

    local characterWasVisible = CharacterFrame and CharacterFrame:IsVisible()
    if characterWasVisible then
        CloseAllBags()
        if HideUIPanel then
            HideUIPanel(CharacterFrame)
        else
            CharacterFrame:Hide()
        end
        if DinoControllerDB.secondaryWindows == 1 and ToggleTalentFrame then
            ToggleTalentFrame()
            if TalentFrame and TalentFrame:IsVisible() and DinoController_RequestTalentFocus then
                DinoController_RequestTalentFocus()
            end
        end
        return
    end

    ToggleCharacter("PaperDollFrame")
    OpenAllBags(1)
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
        -- In a raid, the player is already included exactly once as raidN.
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

    -- In UI mode, the D-pad and Confirm are only rebound temporarily. Do not
    -- save these bindings permanently when switching in the /dino menu; they
    -- are saved correctly when leaving UI mode.
    if save and not uiModeActive then SaveBindings(GetCurrentBindingSet()) end
end

function DinoController_ApplyButtonLayout(save)
    -- In UI mode, D-pad, Confirm, and Cancel are temporarily bound to UI actions.
    -- Event calls (for example UNIT_INVENTORY_CHANGED after buying an item) must
    -- never overwrite the active UI bindings with world actions.
    if uiModeActive then return end

    local function SetPrimaryActionBinding(key)
        local selected = DinoControllerCharacterDB.primaryAction or "Melee"
        local info = primaryActionInfo[selected]
        if selected ~= "Melee" and info and info.available == 1 and info.spellName and SetBindingSpell then
            SetBindingSpell(key, info.spellName)
        else
            SetBinding(key, "TURNORACTION")
        end
    end

    if DinoControllerDB.swapAB == 1 then
        SetBinding("NUMPAD0", "JUMP")           -- Bottom button -> Jump
        SetPrimaryActionBinding("NUMPAD9")       -- Right button -> Confirm / Aktion
    else
        SetPrimaryActionBinding("NUMPAD0")       -- Bottom button -> Confirm / Aktion
        SetBinding("NUMPAD9", "JUMP")           -- Right button -> Jump
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

    if DinoControllerDB.swapMenuButtons == 1 then
        SetActionBinding("NUMPAD5", "DINOCONTROLLER_MENU_CYCLE")
        SetActionBinding("F8", "DINOCONTROLLER_MAP_QUEST_TOGGLE")
    else
        SetActionBinding("NUMPAD5", "DINOCONTROLLER_MAP_QUEST_TOGGLE")
        SetActionBinding("F8", "DINOCONTROLLER_MENU_CYCLE")
    end

    UpdateControllerStatePixel()

    if save then SaveBindings(GetCurrentBindingSet()) end
end

function DinoController_ExecuteXAction()
    if WorldMapIsVisible() then return end
    local slot = 13
    if DinoHUD_TriggerFlashSlot13 then
        DinoHUD_TriggerFlashSlot13()
    end
    if type(slot) == "number" then
        UseAction(slot)
    end
end

function DinoController_ExecuteYAction()
    if WorldMapIsVisible() then return end
    TargetUnit("player")
end

function DinoController_BotAttack()
    if WorldMapIsVisible() then return end
    if DinoController_IsUIModeActive and DinoController_IsUIModeActive() then return end
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    if partyCount < 1 and raidCount < 1 then return end
    if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then return end

    if ChatFrameEditBox then
        ChatFrameEditBox:SetText(".x attack")
        ChatEdit_SendText(ChatFrameEditBox)
    else
        SendChatMessage(".x attack", "SAY")
    end
end

local function ApplyCamera(forceMaximumDistance)
    SafeSetCVar("cameraDistanceMaxFactor", "2")
    SafeSetCVar("cameraYawMoveSpeed", "180")
    SafeSetCVar("cameraPitchMoveSpeed", "90")
    SafeSetCVar("cameraSmoothStyle", "0")
    SafeSetCVar("cameraSmoothTrackingStyle", "0")
    SafeSetCVar("cameraTerrainTilt", "0")
    SafeSetCVar("cameraBobbing", "0")
    SafeSetCVar("cameraPitch", tostring(CAMERA_PITCH))
    -- The client stores the current distance per character in camera-settings.txt.
    -- Login must not overwrite that value; only /dino camera intentionally zooms
    -- out to the maximum.
    if forceMaximumDistance then
        CameraZoomOut(50)
    end
end

local function InstallBindings(force)
    if not force and DinoControllerDB.bindingVersion == BINDING_VERSION then
        return
    end

    -- Restore the arrow keys briefly used for camera bindings to their Vanilla
    -- assignments. Unrelated custom user bindings remain unchanged.
    local obsoleteCameraBindings = {
        { "LEFT", "MOVEVIEWLEFT", "DINOCONTROLLER_CAMERA_LEFT", "TURNLEFT" },
        { "RIGHT", "MOVEVIEWRIGHT", "DINOCONTROLLER_CAMERA_RIGHT", "TURNRIGHT" },
        { "UP", "MOVEVIEWUP", "DINOCONTROLLER_CAMERA_UP", "MOVEFORWARD" },
        { "DOWN", "MOVEVIEWDOWN", "DINOCONTROLLER_CAMERA_DOWN", "MOVEBACKWARD" }
    }
    local obsoleteIndex
    for obsoleteIndex = 1, table.getn(obsoleteCameraBindings) do
        local binding = obsoleteCameraBindings[obsoleteIndex]
        local currentAction = GetBindingAction(binding[1])
        if currentAction == binding[2] or currentAction == binding[3] then
            SetBinding(binding[1], binding[4])
        end
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
    Print("Controller bindings installed.")
end

local reticle = CreateFrame("Frame", "DinoControllerReticle", UIParent)
reticle:SetWidth(14)
reticle:SetHeight(14)
reticle:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
reticle:SetFrameStrata("TOOLTIP")

local horizontal = reticle:CreateTexture(nil, "OVERLAY")
horizontal:SetTexture("Interface\\Buttons\\WHITE8x8")
horizontal:SetVertexColor(0.55, 0.86, 1.0, 1.0)
horizontal:SetWidth(14)
horizontal:SetHeight(2)
horizontal:SetPoint("CENTER", reticle, "CENTER", 0, 0)

local vertical = reticle:CreateTexture(nil, "OVERLAY")
vertical:SetTexture("Interface\\Buttons\\WHITE8x8")
vertical:SetVertexColor(0.55, 0.86, 1.0, 1.0)
vertical:SetWidth(2)
vertical:SetHeight(14)
vertical:SetPoint("CENTER", reticle, "CENTER", 0, 0)

local function UpdateReticle()
    local opacityLevel = DinoControllerDB.reticleOpacityLevel or 3
    reticle:SetAlpha(RETICLE_ALPHA_LEVELS[opacityLevel] or RETICLE_ALPHA_LEVELS[3])
    if DinoControllerDB.controllerEnabled == 1 and DinoControllerDB.showReticle == 1 and
       (not uiModeActive or uiModeContext == "merchant") then
        reticle:Show()
    else
        reticle:Hide()
    end
end

function DinoController_SetUIMode(active, context)
    uiModeActive = active
    uiModeContext = active and context or nil
    UpdateReticle()
end

local function CloseWorldMap()
    if not WorldMapIsVisible() then return end
    if HideUIPanel then
        HideUIPanel(WorldMapFrame)
    else
        ToggleWorldMap()
    end
    if WorldMapIsVisible() and WorldMapFrame.Hide then
        WorldMapFrame:Hide()
    end
end

local function OpenAndFocusQuestLog()
    if not QuestLogFrame or not QuestLogFrame:IsVisible() then
        ToggleQuestLog()
    end
    if DinoController_RequestQuestLogFocus then
        DinoController_RequestQuestLogFocus()
    end
end

function DinoController_ToggleMapQuest()
    if DinoControllerDB.secondaryWindows ~= 1 then
        pendingMapQuestWindow = nil
        nextMapQuestWindow = "map"
        if WorldMapIsVisible() then
            CloseWorldMap()
        else
            ToggleWorldMap()
            if DinoController_RequestWorldMapFocus then
                DinoController_RequestWorldMapFocus()
            end
        end
        return
    end

    if nextMapQuestWindow == "map" then
        pendingMapQuestWindow = nil
        if QuestLogFrame and QuestLogFrame:IsVisible() then
            ToggleQuestLog()
        end
        if not WorldMapIsVisible() then
            ToggleWorldMap()
        end
        if DinoController_RequestWorldMapFocus then
            DinoController_RequestWorldMapFocus()
        end
        nextMapQuestWindow = "questlog"
    else
        nextMapQuestWindow = "map"
        if WorldMapIsVisible() then
            CloseWorldMap()
            pendingMapQuestWindow = "questlog"
        else
            OpenAndFocusQuestLog()
        end
    end
end

-- In Vanilla, WorldMapFrame intercepts all key presses and normally forwards
-- only TOGGLEWORLDMAP and SCREENSHOT. Our map/quest-log binding therefore does
-- not reach the normal binding path while the map is open. The existing
-- controller UI bindings are forwarded to the same RunBinding path here.
local originalWorldMapOnKeyDown = WorldMapFrame and WorldMapFrame:GetScript("OnKeyDown")
if WorldMapFrame then
    local worldMapControllerActions = {
        "DINOCONTROLLER_MAP_QUEST_TOGGLE",
        "DINOCONTROLLER_UI_PREVIOUS",
        "DINOCONTROLLER_UI_NEXT",
        "DINOCONTROLLER_UI_UP",
        "DINOCONTROLLER_UI_DOWN",
        "DINOCONTROLLER_UI_LEFT",
        "DINOCONTROLLER_UI_RIGHT",
        "DINOCONTROLLER_UI_ACTIVATE",
        "DINOCONTROLLER_UI_CANCEL"
    }

    WorldMapFrame:SetScript("OnKeyDown", function()
        local keyPressed = arg1
        if IsShiftKeyDown() then keyPressed = "SHIFT-" .. keyPressed end
        if IsControlKeyDown() then keyPressed = "CTRL-" .. keyPressed end
        if IsAltKeyDown() then keyPressed = "ALT-" .. keyPressed end
        keyPressed = DinoController_NormalizeBindingKey(keyPressed)

        local index
        for index = 1, table.getn(worldMapControllerActions) do
            local action = worldMapControllerActions[index]
            local key1, key2 = GetBindingKey(action)
            if keyPressed == DinoController_NormalizeBindingKey(key1) or
               keyPressed == DinoController_NormalizeBindingKey(key2) then
                RunBinding(action)
                return
            end
        end

        if originalWorldMapOnKeyDown then originalWorldMapOnKeyDown() end
    end)
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
    if not DinoControllerDB or DinoControllerDB.controllerEnabled ~= 0 then return end
    if not LootFrame or not UIParent or not GetCursorPosition then return end

    local parentScale = UIParent:GetEffectiveScale()
    local parentWidth = UIParent:GetWidth()
    local parentHeight = UIParent:GetHeight()
    local frameWidth = LootFrame:GetWidth()
    local frameHeight = LootFrame:GetHeight()
    if not parentScale or parentScale <= 0 or
       not parentWidth or not parentHeight or
       not frameWidth or not frameHeight then
        return
    end

    -- GetCursorPosition returns physical pixels, while frame anchors relative
    -- to UIParent expect its scaled UI coordinates.
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / parentScale
    cursorY = cursorY / parentScale

    local frameScale = LootFrame:GetEffectiveScale() / parentScale
    if not frameScale or frameScale <= 0 then return end
    local visibleWidth = frameWidth * frameScale
    local visibleHeight = frameHeight * frameScale
    local offset = 16

    local left = cursorX + offset
    local bottom = cursorY - offset - visibleHeight
    if left + visibleWidth > parentWidth then
        left = cursorX - offset - visibleWidth
    end
    if bottom < 0 then
        bottom = cursorY + offset
    end

    -- Keep the entire window inside UIParent even at extreme cursor positions
    -- and low resolutions.
    left = math.max(0, math.min(left, math.max(0, parentWidth - visibleWidth)))
    bottom = math.max(0, math.min(bottom, math.max(0, parentHeight - visibleHeight)))

    LootFrame:ClearAllPoints()
    LootFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
end

local function MarkQuestListAmbiguous()
    if not ambiguousQuestList then
        Print("Multiple quests are available - select one.")
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

local function QuestLogEntryKey(index)
    local title, level, questTag, isHeader = GetQuestLogTitle(index)
    if not title or isHeader then return nil end
    return title .. "\031" .. tostring(level or "") .. "\031" .. tostring(questTag or "")
end

local function CaptureQuestLogSnapshot()
    local snapshot = {}
    local entryCount = GetNumQuestLogEntries() or 0
    local index
    for index = 1, entryCount do
        local key = QuestLogEntryKey(index)
        if key then snapshot[key] = (snapshot[key] or 0) + 1 end
    end
    return snapshot
end

local function TrackNewlyAcceptedQuest()
    if not pendingQuestWatchSnapshot then return end
    if DinoControllerDB.autoTrackQuest ~= 1 then
        pendingQuestWatchSnapshot = nil
        pendingQuestWatchUntil = nil
        return
    end

    local oldEntriesSeen = {}
    local entryCount = GetNumQuestLogEntries() or 0
    local addedWatch = nil
    local index
    for index = 1, entryCount do
        local key = QuestLogEntryKey(index)
        if key then
            local occurrence = (oldEntriesSeen[key] or 0) + 1
            oldEntriesSeen[key] = occurrence
            if occurrence > (pendingQuestWatchSnapshot[key] or 0) then
                if pcall(AddQuestWatch, index) then addedWatch = 1 end
            end
        end
    end

    if addedWatch then
        if QuestWatch_Update then pcall(QuestWatch_Update) end
        pendingQuestWatchSnapshot = nil
        pendingQuestWatchUntil = nil
    end
end

-- Vanilla 1.12.1 has no QUEST_ACCEPTED event. The original AcceptQuest function
-- remains the trigger; QUEST_LOG_UPDATE then supplies the actual quest-log
-- index for AddQuestWatch.
local original_AcceptQuest = AcceptQuest
if original_AcceptQuest then
    function AcceptQuest()
        if DinoControllerDB.autoTrackQuest == 1 then
            pendingQuestWatchSnapshot = CaptureQuestLogSnapshot()
            pendingQuestWatchUntil = GetTime() + 5
        else
            pendingQuestWatchSnapshot = nil
            pendingQuestWatchUntil = nil
        end
        original_AcceptQuest()
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
            Print("Multiple rewards - choose with the D-pad and press Confirm.")
        elseif DinoControllerDB.autoQuest == 1 then
            if choices == 1 then GetQuestReward(1) else GetQuestReward(0) end
        end
    elseif eventName == "QUEST_FINISHED" or eventName == "GOSSIP_CLOSED" then
        ambiguityClearAt = GetTime() + 5
    elseif eventName == "QUEST_LOG_UPDATE" then
        TrackNewlyAcceptedQuest()
    end
end

function DinoController_SetControllerEnabled(enabled)
    local state = enabled and 1 or 0
    DinoControllerDB.controllerEnabled = state
    if state == 1 then
        InstallBindings(true)
        if DinoHUD_UpdateVisibility then DinoHUD_UpdateVisibility() end
        UpdateReticle()
        Print("Controller support: |cff55ff77ON|r")
    else
        if DinoController_LeaveUIMode then DinoController_LeaveUIMode() end
        if DinoHUD_UpdateVisibility then DinoHUD_UpdateVisibility() end
        UpdateReticle()
        Print("Controller support: |cffff5555OFF|r")
    end
    if UpdateMenu then UpdateMenu() end
end

local menu = CreateFrame("Frame", "DinoControllerMenu", UIParent)
menu:SetWidth(590)
menu:SetHeight(520)
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

local function CreateSectionTitle(x, y, text)
    local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", menu, "TOPLEFT", x, y)
    title:SetText(text)
    return title
end

local function CreateMenuButtonAt(x, y, width, callback)
    local button = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
    button:SetWidth(width or 210)
    button:SetHeight(25)
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", x, y)
    button:SetScript("OnClick", callback)
    return button
end

local controllerButton
local reticleButton
local reticleOpacityButton
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
local xActionSlotText
local autoTrackQuestButton
local swapMenuButtonsButton
local secondaryWindowsButton
local dpadLayoutButton
local hudLayoutButton
local groundSpellButton
local controllerEmphasis
local primaryActionText

local function UpdateMenu()
    EnsureDefaults()
    controllerButton:SetText("Controller support: " .. OnOff(DinoControllerDB.controllerEnabled))
    reticleButton:SetText("Reticle: " .. OnOff(DinoControllerDB.showReticle))
    if reticleOpacityButton then reticleOpacityButton:SetText("Reticle opacity: " .. (DinoControllerDB.reticleOpacityLevel or 3)) end
    autoQuestButton:SetText("Auto Quest: " .. OnOff(DinoControllerDB.autoQuest))
    hudButton:SetText("Controller-HUD: " .. OnOff(DinoControllerHUDDB and DinoControllerHUDDB.hudVisible or 1))
    hudLockButton:SetText("HUD position: " .. ((DinoControllerHUDDB and DinoControllerHUDDB.hudLocked == 1) and "Locked" or "Unlocked"))
    swapABButton:SetText("Swap A/B: " .. OnOff(DinoControllerDB.swapAB))
    swapXYButton:SetText("Swap X/Y: " .. OnOff(DinoControllerDB.swapXY))
    targetDpsButton:SetText(DinoControllerDB.targetMode == "dps" and "[ DPS/Tank ]" or "DPS/Tank")
    targetHealerButton:SetText(DinoControllerDB.targetMode == "healer" and "[ Healer ]" or "Healer")
    if autoTrackQuestButton then autoTrackQuestButton:SetText("Auto-track quests: " .. OnOff(DinoControllerDB.autoTrackQuest)) end
    if swapMenuButtonsButton then swapMenuButtonsButton:SetText("Swap Select/Start: " .. OnOff(DinoControllerDB.swapMenuButtons)) end
    if secondaryWindowsButton then secondaryWindowsButton:SetText("Secondary windows: " .. OnOff(DinoControllerDB.secondaryWindows)) end
    if dpadLayoutButton then dpadLayoutButton:SetText("D-pad layout: " .. ((DinoControllerDB.dpadLayout == "Mitte") and "Center" or "Standard")) end
    if hudLayoutButton then hudLayoutButton:SetText("HUD layout: " .. ((DinoControllerDB.hudLayout == "Seitlich") and "Side" or "Bottom")) end
    if groundSpellButton then
        groundSpellButton:SetText("Auto ground spells: " .. OnOff(DinoController_GetGroundSpellMode()))
    end
    DinoController_RefreshPrimaryAction()
    if primaryActionText then
        local info = DinoController_GetPrimaryActionInfo()
        primaryActionText:SetText(info and info.label or "Attack")
    end
    if controllerEmphasis then
        if DinoControllerDB.controllerEnabled == 1 then
            controllerEmphasis:SetBackdropColor(0.03, 0.22, 0.08, 0.95)
            controllerEmphasis:SetBackdropBorderColor(0.25, 1.0, 0.42, 1)
        else
            controllerEmphasis:SetBackdropColor(0.28, 0.04, 0.04, 0.95)
            controllerEmphasis:SetBackdropBorderColor(1.0, 0.25, 0.20, 1)
        end
    end

end

controllerButton = CreateMenuButtonAt(18, -50, 552, function()
    DinoController_SetControllerEnabled(DinoControllerDB.controllerEnabled ~= 1)
end)
controllerButton:SetHeight(30)

controllerEmphasis = CreateFrame("Frame", nil, menu)
controllerEmphasis:SetPoint("TOPLEFT", controllerButton, "TOPLEFT", -4, 4)
controllerEmphasis:SetPoint("BOTTOMRIGHT", controllerButton, "BOTTOMRIGHT", 4, -4)
controllerEmphasis:SetFrameLevel(controllerButton:GetFrameLevel() - 1)
controllerEmphasis:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})

CreateSectionTitle(18, -96, "CONTROLS")
CreateSectionTitle(208, -96, "BUTTONS")
CreateSectionTitle(398, -96, "QUEST")
CreateSectionTitle(398, -202, "DISPLAY")
CreateSectionTitle(18, -374, "INFO")

reticleButton = CreateMenuButtonAt(398, -224, 170, function()
    DinoControllerDB.showReticle = DinoControllerDB.showReticle == 1 and 0 or 1
    UpdateReticle()
    UpdateMenu()
end)

reticleOpacityButton = CreateMenuButtonAt(398, -254, 170, function()
    local level = DinoControllerDB.reticleOpacityLevel or 3
    if level >= 3 then level = 1 else level = level + 1 end
    DinoControllerDB.reticleOpacityLevel = level
    UpdateReticle()
    UpdateMenu()
end)

autoQuestButton = CreateMenuButtonAt(398, -118, 170, function()
    DinoControllerDB.autoQuest = DinoControllerDB.autoQuest == 1 and 0 or 1
    UpdateMenu()
end)

hudButton = CreateMenuButtonAt(398, -284, 170, function()
    if DinoControllerHUDDB then
        if DinoControllerHUDDB.hudVisible == 1 then
            if DinoHUD_Hide then DinoHUD_Hide() end
        else
            if DinoHUD_Show then DinoHUD_Show() end
        end
    end
    UpdateMenu()
end)

hudLockButton = CreateMenuButtonAt(398, -314, 170, function()
    if DinoControllerHUDDB then
        if DinoControllerHUDDB.hudLocked == 1 then
            if DinoHUD_Unlock then DinoHUD_Unlock() end
        else
            if DinoHUD_Lock then DinoHUD_Lock() end
        end
    end
    UpdateMenu()
end)

hudLayoutButton = CreateMenuButtonAt(398, -344, 170, function()
    if DinoControllerDB.hudLayout == "Seitlich" then
        DinoControllerDB.hudLayout = "Unten"
    else
        DinoControllerDB.hudLayout = "Seitlich"
    end
    if DinoHUD_ApplyLayout then DinoHUD_ApplyLayout() end
    UpdateMenu()
end)

swapABButton = CreateMenuButtonAt(208, -118, 170, function()
    DinoControllerDB.swapAB = DinoControllerDB.swapAB == 1 and 0 or 1
    DinoController_ApplyButtonLayout(true)
    if DinoController_IsUIModeActive and DinoController_IsUIModeActive() then
        if DinoController_LeaveUIMode then DinoController_LeaveUIMode() end
    end
    UpdateMenu()
    if DinoHUD_UpdateLabels then DinoHUD_UpdateLabels() end
end)

swapXYButton = CreateMenuButtonAt(208, -148, 170, function()
    DinoControllerDB.swapXY = DinoControllerDB.swapXY == 1 and 0 or 1
    DinoController_ApplyButtonLayout(true)
    UpdateMenu()
    if DinoHUD_UpdateLabels then DinoHUD_UpdateLabels() end
end)

dpadLayoutButton = CreateMenuButtonAt(18, -118, 170, function()
    if DinoControllerDB.dpadLayout == "Mitte" then
        DinoControllerDB.dpadLayout = "Standard"
    else
        DinoControllerDB.dpadLayout = "Mitte"
    end
    if DinoHUD_UpdateActivePage then DinoHUD_UpdateActivePage() end
    UpdateMenu()
end)

groundSpellButton = CreateMenuButtonAt(18, -148, 170, function()
    DinoControllerDB.groundSpellMode = DinoController_GetGroundSpellMode() == 1 and 0 or 1
    UpdateMenu()
end)

local targetModeTitle = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
targetModeTitle:SetPoint("TOPLEFT", menu, "TOPLEFT", 18, -230)
targetModeTitle:SetText("Target mode")

targetDpsButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
targetDpsButton:SetWidth(170)
targetDpsButton:SetHeight(22)
targetDpsButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 18, -252)
targetDpsButton:SetScript("OnClick", function()
    DinoControllerDB.targetMode = "dps"
    DinoController_ApplyTargetMode(true)
    UpdateMenu()
    Print("Target mode: DPS/Tank.")
end)

targetHealerButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
targetHealerButton:SetWidth(170)
targetHealerButton:SetHeight(22)
targetHealerButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 18, -278)
targetHealerButton:SetScript("OnClick", function()
    DinoControllerDB.targetMode = "healer"
    DinoController_ApplyTargetMode(true)
    UpdateMenu()
    Print("Target mode: Healer.")
end)

autoTrackQuestButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
autoTrackQuestButton:SetWidth(170)
autoTrackQuestButton:SetHeight(22)
autoTrackQuestButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 398, -148)
autoTrackQuestButton:SetScript("OnClick", function()
    DinoControllerDB.autoTrackQuest = DinoControllerDB.autoTrackQuest == 1 and 0 or 1
    if DinoControllerDB.autoTrackQuest ~= 1 then
        pendingQuestWatchSnapshot = nil
        pendingQuestWatchUntil = nil
    end
    UpdateMenu()
end)

swapMenuButtonsButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
swapMenuButtonsButton:SetWidth(170)
swapMenuButtonsButton:SetHeight(22)
swapMenuButtonsButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 208, -178)
swapMenuButtonsButton:SetScript("OnClick", function()
    DinoControllerDB.swapMenuButtons = DinoControllerDB.swapMenuButtons == 1 and 0 or 1
    DinoController_ApplyButtonLayout(true)
    UpdateMenu()
end)

secondaryWindowsButton = CreateMenuButtonAt(208, -208, 170, function()
    DinoControllerDB.secondaryWindows = DinoControllerDB.secondaryWindows == 1 and 0 or 1
    if DinoControllerDB.secondaryWindows ~= 1 then
        pendingMapQuestWindow = nil
        nextMapQuestWindow = "map"
    end
    UpdateMenu()
end)

local dmmButton = CreateMenuButtonAt(208, -248, 170, function()
    local dmmFrame = getglobal and getglobal("DinoMacroManagerFrame")
    menu:Hide()
    if dmmFrame and dmmFrame:IsShown() then return end
    if DinoMacroManager_Toggle then
        DinoMacroManager_Toggle()
    else
        Print("DinoMacroManager is not loaded.")
    end
end)
dmmButton:SetText("DinoMacroManager")

local dmmInfoText = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dmmInfoText:SetPoint("TOPLEFT", menu, "TOPLEFT", 208, -278)
dmmInfoText:SetWidth(170)
dmmInfoText:SetJustifyH("LEFT")
dmmInfoText:SetText("Build custom 2-4 step spell chains and manage up to 14 macro slots.\n\n|cffffff77Open with /dmm|r")

local infoText = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
infoText:SetPoint("TOPLEFT", menu, "TOPLEFT", 18, -396)
infoText:SetJustifyH("LEFT")
infoText:SetWidth(552)
infoText:SetText("|cff33ff99Info:|r\n" ..
                 "Bar 1: controller frames highlight groups 1-4, 5-8 and 9-12.\n" ..
                 "Bar 2: the X/Y button is assignable; the mount sits beside it.\n" ..
                 "D-pad Standard: no modifier = 1-4, R1/L2 = 5-8, R2 = 9-12.\n" ..
                 "D-pad Center: no modifier = 5-8, R1/L2 = 1-4, R2 = 9-12.\n" ..
                 "|cffffff77/dino bind|r - reinstall controller bindings")

local infoPopup = CreateFrame("Frame", "DinoControllerInfoPopup", UIParent)
infoPopup:SetWidth(480)
infoPopup:SetHeight(340)
infoPopup:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
infoPopup:SetFrameStrata("DIALOG")
infoPopup:SetFrameLevel(menu:GetFrameLevel() + 10)
infoPopup:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
})
infoPopup:SetBackdropColor(0.02, 0.04, 0.08, 0.98)
infoPopup:SetBackdropBorderColor(0.34, 0.67, 0.92, 1)
infoPopup:EnableMouse(true)
infoPopup:SetMovable(true)
infoPopup:RegisterForDrag("LeftButton")
infoPopup:SetScript("OnDragStart", function() this:StartMoving() end)
infoPopup:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
infoPopup:Hide()

if UISpecialFrames then
    table.insert(UISpecialFrames, "DinoControllerInfoPopup")
end

local infoPopupTitle = infoPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
infoPopupTitle:SetPoint("TOPLEFT", infoPopup, "TOPLEFT", 16, -16)
infoPopupTitle:SetPoint("TOPRIGHT", infoPopup, "TOPRIGHT", -16, -16)
infoPopupTitle:SetJustifyH("LEFT")
infoPopupTitle:SetText("|cffffcc00These features are not available from the controller:|r")

local infoPopupBody = infoPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
infoPopupBody:SetPoint("TOPLEFT", infoPopupTitle, "BOTTOMLEFT", 0, -10)
infoPopupBody:SetPoint("TOPRIGHT", infoPopup, "TOPRIGHT", -16, -40)
infoPopupBody:SetJustifyH("LEFT")
infoPopupBody:SetText(
    "|cffff7777-|r Mailbox (send mail)\n" ..
    "|cffff7777-|r Create auctions (Auction House)\n" ..
    "|cffff7777-|r Open the spellbook and place spells on action bars\n" ..
    "|cffff7777-|r Chat and friends features\n" ..
    "|cffff7777-|r Advanced bot controls\n" ..
    "  |cff88aaff(BOT ATTACK - assignable action in Macro Manager)|r\n\n" ..
    "|cff7fc8ffAction-bar note:|r\n" ..
    "The default layout supports 14 direct controller actions.\n" ..
    "|cff33ff99More actions and spell chains through DinoMacroManager:|r\n" ..
    "|cffffff77/dmm|r"
)

local infoPopupClose = CreateFrame("Button", nil, infoPopup, "UIPanelButtonTemplate")
infoPopupClose:SetWidth(80)
infoPopupClose:SetHeight(22)
infoPopupClose:SetPoint("BOTTOMRIGHT", infoPopup, "BOTTOMRIGHT", -14, 14)
infoPopupClose:SetText("Close")
infoPopupClose:SetScript("OnClick", function() infoPopup:Hide() end)

local function ToggleInfoPopup()
    if infoPopup:IsVisible() then
        infoPopup:Hide()
    else
        infoPopup:Show()
    end
end

local infoButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
infoButton:SetWidth(130)
infoButton:SetHeight(25)
infoButton:SetPoint("BOTTOMLEFT", menu, "BOTTOMLEFT", 18, 16)
infoButton:SetText("Controller info")
infoButton:SetScript("OnClick", ToggleInfoPopup)

local closeButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
closeButton:SetWidth(90)
closeButton:SetHeight(25)
closeButton:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -18, 16)
closeButton:SetText("Close")
closeButton:SetScript("OnClick", function()
    infoPopup:Hide()
    menu:Hide()
end)

local function ToggleMenu()
    if menu:IsVisible() then
        infoPopup:Hide()
        menu:Hide()
    else
        UpdateMenu()
        menu:Show()
    end
end

local function SetOption(name, value)
    local enabled
    if value == "on" or value == "an" or value == "1" then enabled = 1 end
    if value == "off" or value == "aus" or value == "0" then enabled = 0 end
    if enabled == nil then
        Print("Enter 'on' or 'off'.")
        return
    end

    DinoControllerDB[name] = enabled
    if name == "showReticle" then UpdateReticle() end
    if name == "autoLoot" then ApplyAutoLootSetting() end
    UpdateMenu()
end

local function PrintStatus()
    Print("Controller " .. OnOff(DinoControllerDB.controllerEnabled) ..
        ", Reticle " .. OnOff(DinoControllerDB.showReticle) ..
        ", UI " .. OnOff(DinoControllerDB.uiEnabled) ..
        ", AutoQuest " .. OnOff(DinoControllerDB.autoQuest) ..
        ", AutoLoot " .. OnOff(DinoControllerDB.autoLoot) ..
        ", Auto ground spells " .. OnOff(DinoController_GetGroundSpellMode()) ..
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
        ApplyCamera(true)
        Print("Camera settings reapplied.")
    elseif command == "bind" or command == "bindings" then
        InstallBindings(true)
    -- German command/value aliases are retained internally for backward
    -- compatibility with existing macros and are not listed in player help.
    elseif command == "reticle" or command == "fadenkreuz" then
        if value == "" then
            DinoControllerDB.showReticle = DinoControllerDB.showReticle == 1 and 0 or 1
            UpdateReticle()
            UpdateMenu()
        else
            SetOption("showReticle", value)
        end
        Print("Reticle " .. OnOff(DinoControllerDB.showReticle) .. ".")
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
    elseif command == "ground" or command == "boden" or command == "bodenzauber" then
        if value == "" then
            DinoControllerDB.groundSpellMode = DinoController_GetGroundSpellMode() == 1 and 0 or 1
            UpdateMenu()
        else
            SetOption("groundSpellMode", value)
        end
        Print("Auto ground spells " .. OnOff(DinoController_GetGroundSpellMode()) .. ".")
    elseif command == "layout" then
        if value == "xbox" or value == "nintendo" then
            DinoControllerDB.buttonLayout = value
            DinoControllerDB.swapAB = value == "nintendo" and 1 or 0
            DinoControllerDB.layoutMappingVersion = 2
            if not uiModeActive then DinoController_ApplyButtonLayout(1) end
            UpdateMenu()
            Print("Button Layout: " .. (value == "nintendo" and "Nintendo" or "Xbox") .. ".")
        else
            Print("Use '/dino layout xbox' or '/dino layout nintendo'.")
        end
    elseif command == "target" or command == "targetmode" then
        if value == "healer" or value == "heal" then
            DinoControllerDB.targetMode = "healer"
            DinoController_ApplyTargetMode(true)
            UpdateMenu()
            Print("Target mode: Healer.")
        elseif value == "dps" or value == "tank" or value == "dpstank" then
            DinoControllerDB.targetMode = "dps"
            DinoController_ApplyTargetMode(true)
            UpdateMenu()
            Print("Target mode: DPS/Tank.")
        else
            Print("Use '/dino target dps' or '/dino target healer'.")
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
        Print("/dino | controller on/off | target dps/healer | ground on/off | reticle on/off | ui on/off | autoquest on/off | autoloot on/off | status")
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
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("GOSSIP_CLOSED")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00DinoController: /dino opens the settings menu|r")
        end
        InstallBindings(false)
        -- Reapply the saved A/B toggle at every login, even when the binding
        -- version has not changed.
        DinoController_RefreshPrimaryAction()
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
    elseif event == "SPELLS_CHANGED" or (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player") then
        DinoController_RefreshPrimaryAction()
        if not uiModeActive then
            DinoController_ApplyButtonLayout(nil)
        end
        if menu:IsVisible() then UpdateMenu() end
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
    if pendingMapQuestWindow == "questlog" then
        if WorldMapIsVisible() then
            CloseWorldMap()
        else
            pendingMapQuestWindow = nil
            OpenAndFocusQuestLog()
        end
    end

    if this.pendingCamera then
        this.pendingCamera = this.pendingCamera - 1
        if this.pendingCamera <= 0 then
            ApplyCamera()
            this.pendingCamera = nil
        end
    end

    UpdateControllerStatePixel()

    if ambiguityClearAt and GetTime() >= ambiguityClearAt then
        ambiguousQuestList = nil
        ambiguityClearAt = nil
    end

    if pendingQuestWatchUntil and GetTime() >= pendingQuestWatchUntil then
        pendingQuestWatchSnapshot = nil
        pendingQuestWatchUntil = nil
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
