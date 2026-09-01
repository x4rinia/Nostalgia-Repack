-- DinoControllerHUD.lua – Controller-HUD mit frei belegbaren ActionSlots
-- Author: x4rinia
-- Vanilla 1.12.1 stellt 120 ActionSlots bereit.
-- Die 4 D-Pad-Slots bedienen die untere WoW-Actionbar (Slots 1–12):
--   Ohne Modifier: Slots 1–4
--   L2 gehalten:   Slots 5–8
--   R2 gehalten:   Slots 9–12
-- Slot 5 (X):      Frei belegbare Aktion (ActionSlot 13)
-- Slot 6 (R3):     Mount (ActionSlot 78)

DinoControllerHUDDB = DinoControllerHUDDB or {}

local HUD_SLOTS = {
    { id = 1, name = "DPadUp",    actionSlot = 1,  label = "UP", arrow = "↑" },
    { id = 2, name = "DPadRight", actionSlot = 2,  label = "RT", arrow = "→" },
    { id = 3, name = "DPadDown",  actionSlot = 3,  label = "DN", arrow = "↓" },
    { id = 4, name = "DPadLeft",  actionSlot = 4,  label = "LT", arrow = "←" },
    { id = 5, name = "XAction",   actionSlot = 13,  label = "X",  arrow = nil },
    { id = 6, name = "Mount",     actionSlot = 14,  label = "R3", arrow = nil },
    { id = 7, name = "AButton",   actionSlot = nil, label = "A",  arrow = nil },
    { id = 8, name = "Target",    actionSlot = nil, label = "Y",  arrow = nil },
}

local HUD_BUTTON_SIZE = 36
local HUD_SPACING = 4
local HUD_UPDATE_INTERVAL = 0.1
local hudLocked = true
local hudVisible = true
local hudButtons = {}
local hudFrame = nil
local hudUpdateElapsed = 0

local l2Held = false
local r2Held = false
local lastMod = nil
local actionbarGroups = {}
local actionbarSlot13 = nil
local actionbarSlot14 = nil
local flashSlot13Until = nil
local flashSlot14Until = nil

function DinoHUD_UpdateLabels()
    if DinoControllerDB and DinoControllerDB.swapAB == 1 then
        HUD_SLOTS[7].label = "B" -- physical bottom
    else
        HUD_SLOTS[7].label = "A" -- physical bottom
    end

    for i = 1, 8 do
        if hudButtons[i] and hudButtons[i].nameText then
            hudButtons[i].nameText:Hide()
        end
    end

    local xActionButton = (DinoControllerDB and DinoControllerDB.swapXY == 1) and "Y" or "X"
    HUD_SLOTS[5].label = xActionButton

    if hudFrame and hudFrame.xHint then
        hudFrame.xHint:SetText("|cffaaaaaa" .. xActionButton .. "|r")
    end
end

-- =========================================================================
-- Hilfsfunktionen
-- =========================================================================

local function HUDPrint(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fc8ffDinoController HUD:|r " .. msg)
    end
end

local function EnsureHUDDefaults()
    if DinoControllerHUDDB.posX == nil then DinoControllerHUDDB.posX = 0 end
    if DinoControllerHUDDB.posY == nil then DinoControllerHUDDB.posY = -200 end
    if DinoControllerHUDDB.hudVisible == nil then DinoControllerHUDDB.hudVisible = 1 end
    if DinoControllerHUDDB.hudLocked == nil then DinoControllerHUDDB.hudLocked = 1 end
end

-- =========================================================================
-- Modifier-System (L2 / R2)
-- =========================================================================

local function UpdateAllButtons()
    local i
    for i = 1, 8 do
        if hudButtons[i] then
            hudButtons[i]:UpdateDisplay()
        end
    end
end

function DinoHUD_RefreshPrimaryAction()
    DinoHUD_UpdateLabels()
    UpdateAllButtons()
end

function DinoHUD_GetPageOffset()
    local layout = (DinoControllerDB and DinoControllerDB.dpadLayout) or "Standard"

    if layout == "Mitte" then
        if r2Held and l2Held then
            return (lastMod == "R2") and 8 or 0
        elseif r2Held then
            return 8
        elseif l2Held then
            return 0
        end
        return 4
    end

    if r2Held and l2Held then
        return (lastMod == "R2") and 8 or 4
    elseif r2Held then
        return 8
    elseif l2Held then
        return 4
    end
    return 0
end

function DinoHUD_UpdateActivePage()
    local offset = DinoHUD_GetPageOffset()
    local i
    for i = 1, 4 do
        if hudButtons[i] then
            hudButtons[i].dinoActionSlot = i + offset
        end
    end
    UpdateAllButtons()
    if DinoHUD_UpdateActionbarHighlights then
        DinoHUD_UpdateActionbarHighlights()
    end
end

function DinoHUD_SetModifier(mod, isDown)
    if mod == "L2" then
        l2Held = isDown
        if isDown then lastMod = "L2" end
    elseif mod == "R2" then
        r2Held = isDown
        if isDown then lastMod = "R2" end
    end
    DinoHUD_UpdateActivePage()
end

local function CreateActionbarHighlight(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(false)
    frame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 22,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:Hide()
    return frame
end

local function EnsureActionbarHighlights()
    if not actionbarGroups[1] then
        actionbarGroups[1] = CreateActionbarHighlight("DinoControllerGroupFrame1")
        actionbarGroups[2] = CreateActionbarHighlight("DinoControllerGroupFrame2")
        actionbarGroups[3] = CreateActionbarHighlight("DinoControllerGroupFrame3")
        actionbarSlot13 = CreateActionbarHighlight("DinoControllerGroupFrameSlot13")
        actionbarSlot14 = CreateActionbarHighlight("DinoControllerGroupFrameSlot14")
    end
end

local function HideAllActionbarHighlights()
    local index
    for index = 1, 3 do
        if actionbarGroups[index] then
            actionbarGroups[index]:Hide()
        end
    end
    if actionbarSlot13 then actionbarSlot13:Hide() end
    if actionbarSlot14 then actionbarSlot14:Hide() end
end

function DinoHUD_UpdateActionbarHighlights()
    EnsureActionbarHighlights()

    if not DinoControllerDB or DinoControllerDB.controllerEnabled ~= 1 then
        HideAllActionbarHighlights()
        return
    end

    local page = CURRENT_ACTIONBAR_PAGE or 1
    local index

    if page == 1 then
        if actionbarSlot13 then actionbarSlot13:Hide() end
        if actionbarSlot14 then actionbarSlot14:Hide() end

        for index = 1, 3 do
            local startSlot = ((index - 1) * 4) + 1
            local endSlot = startSlot + 3
            local startBtn = getglobal("ActionButton" .. startSlot)
            local endBtn = getglobal("ActionButton" .. endSlot)

            if startBtn and endBtn and actionbarGroups[index] then
                local frame = actionbarGroups[index]
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", startBtn, "TOPLEFT", -8, 8)
                frame:SetPoint("BOTTOMRIGHT", endBtn, "BOTTOMRIGHT", 8, -8)

                local offset = DinoHUD_GetPageOffset()
                local activeGroup = 1
                if offset == 4 then
                    activeGroup = 2
                elseif offset == 8 then
                    activeGroup = 3
                end

                if index == activeGroup then
                    frame:SetBackdropBorderColor(0.2, 0.9, 0.4, 1.0)
                    frame:SetAlpha(1.0)
                else
                    frame:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.5)
                    frame:SetAlpha(0.6)
                end

                frame:Show()
            elseif actionbarGroups[index] then
                actionbarGroups[index]:Hide()
            end
        end
        return
    end

    for index = 1, 3 do
        if actionbarGroups[index] then
            actionbarGroups[index]:Hide()
        end
    end

    if page == 2 then
        local button1 = getglobal("ActionButton1")
        local button2 = getglobal("ActionButton2")

        if button1 and actionbarSlot13 then
            actionbarSlot13:ClearAllPoints()
            actionbarSlot13:SetPoint("TOPLEFT", button1, "TOPLEFT", -8, 8)
            actionbarSlot13:SetPoint("BOTTOMRIGHT", button1, "BOTTOMRIGHT", 8, -8)
            if flashSlot13Until and GetTime() < flashSlot13Until then
                actionbarSlot13:SetBackdropBorderColor(0.2, 0.6, 1.0, 1.0)
            else
                actionbarSlot13:SetBackdropBorderColor(0.2, 0.9, 0.4, 1.0)
            end
            actionbarSlot13:SetAlpha(1.0)
            actionbarSlot13:Show()
        elseif actionbarSlot13 then
            actionbarSlot13:Hide()
        end

        if button2 and actionbarSlot14 then
            actionbarSlot14:ClearAllPoints()
            actionbarSlot14:SetPoint("TOPLEFT", button2, "TOPLEFT", -8, 8)
            actionbarSlot14:SetPoint("BOTTOMRIGHT", button2, "BOTTOMRIGHT", 8, -8)
            if flashSlot14Until and GetTime() < flashSlot14Until then
                actionbarSlot14:SetBackdropBorderColor(0.2, 0.6, 1.0, 1.0)
            else
                actionbarSlot14:SetBackdropBorderColor(0.2, 0.9, 0.4, 1.0)
            end
            actionbarSlot14:SetAlpha(1.0)
            actionbarSlot14:Show()
        elseif actionbarSlot14 then
            actionbarSlot14:Hide()
        end
        return
    end

    if actionbarSlot13 then actionbarSlot13:Hide() end
    if actionbarSlot14 then actionbarSlot14:Hide() end
end

function DinoHUD_TriggerFlashSlot13()
    flashSlot13Until = GetTime() + 0.2
    DinoHUD_UpdateActionbarHighlights()
end

function DinoHUD_TriggerFlashSlot14()
    flashSlot14Until = GetTime() + 0.2
    DinoHUD_UpdateActionbarHighlights()
end

-- =========================================================================
-- Einzelnen HUD-Button erstellen
-- =========================================================================

local function DinoHUD_GetActionSlotDMMInfo(actionSlot)
    if not actionSlot then return nil end
    local dmmIndex = nil
    if DinoMacroManager_GetSlotFromAction then
        dmmIndex = DinoMacroManager_GetSlotFromAction(actionSlot)
    end
    if not dmmIndex and type(GetActionText) == "function" then
        local text = GetActionText(actionSlot)
        if text then
            local _, _, num = string.find(text, "^DMM Slot (%d+)$")
            if num then dmmIndex = tonumber(num) end
        end
    end
    if not dmmIndex then return nil end

    local spell, bookIndex
    if DinoMacroManager_GetSlotCurrentSpell then
        spell, bookIndex = DinoMacroManager_GetSlotCurrentSpell(dmmIndex)
    end

    local start, duration, enable = 0, 0, 0
    if DinoMacroManager_GetSlotCooldown then
        start, duration, enable = DinoMacroManager_GetSlotCooldown(dmmIndex)
    elseif bookIndex and spell then
        start, duration, enable = GetSpellCooldown(bookIndex, spell.bookType or "spell")
    end

    local isUsable, notEnoughMana = true, false
    if DinoMacroManager_IsSlotUsable then
        isUsable, notEnoughMana = DinoMacroManager_IsSlotUsable(dmmIndex)
    end

    local inRange = nil
    if DinoMacroManager_IsSlotInRange then
        inRange = DinoMacroManager_IsSlotInRange(dmmIndex, "target")
    end

    return {
        index = dmmIndex,
        spell = spell,
        bookIndex = bookIndex,
        texture = spell and spell.icon,
        cooldownStart = start,
        cooldownDuration = duration,
        cooldownEnable = enable,
        isUsable = isUsable,
        notEnoughMana = notEnoughMana,
        inRange = inRange
    }
end

local function CreateHUDButton(parent, slotInfo, index)
    local btnName = "DinoHUDButton" .. slotInfo.id
    local size = HUD_BUTTON_SIZE

    local btn = CreateFrame("CheckButton", btnName, parent, "ActionButtonTemplate")
    btn:SetWidth(size)
    btn:SetHeight(size)
    btn:EnableMouse(true)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn.dinoSlotInfo = slotInfo
    btn.dinoActionSlot = slotInfo.actionSlot

    local icon = getglobal(btnName .. "Icon")
    local cooldown = getglobal(btnName .. "Cooldown")
    local count = getglobal(btnName .. "Count")
    local normalTexture = getglobal(btnName .. "NormalTexture")
    local hotkey = getglobal(btnName .. "HotKey")
    local name = getglobal(btnName .. "Name")

    btn.nameText = name
    btn.nameText:Hide()

    if hotkey then
        if slotInfo.id < 5 then
            if slotInfo.arrow then
                hotkey:SetText(slotInfo.arrow)
            else
                hotkey:SetText(slotInfo.label)
            end
            hotkey:Show()
        else
            hotkey:Hide()
        end
    end

    if slotInfo.arrow then
        local dirTag = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dirTag:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        dirTag:SetText(slotInfo.arrow)
        dirTag:SetTextColor(0.45, 0.85, 1.0, 0.95)
        dirTag:Show()
    end

    if name then name:Hide() end

    if normalTexture then
        normalTexture:SetVertexColor(0.6, 0.6, 0.6, 0.8)
    end

    btn.icon = icon
    btn.cooldown = cooldown
    btn.countText = count

    -- =================================================================
    -- UpdateDisplay der Aktionsslots und Sondertasten
    -- =================================================================
    btn.UpdateDisplay = function(self)
        self.nameText:Hide()
        if self.dinoSlotInfo.id == 8 then
            if self.icon then
                SetPortraitTexture(self.icon, "player")
                self.icon:Show()
                self.icon:SetVertexColor(1.0, 1.0, 1.0)
            end
            self:SetAlpha(1.0)
            if self.countText then self.countText:Hide() end
            if self.cooldown then CooldownFrame_SetTimer(self.cooldown, 0, 0, 0) end
            return
        end

        if self.dinoSlotInfo.id == 7 then
            -- A-Taste: ausgewaehlte Primaeraktion / Interaktion
            local actionInfo = DinoController_GetPrimaryActionInfo and DinoController_GetPrimaryActionInfo()
            if self.icon then
                self.icon:SetTexture(actionInfo and actionInfo.texture or "Interface\\Icons\\Ability_MeleeDamage")
                self.icon:Show()
                self.icon:SetVertexColor(1.0, 1.0, 1.0)
            end
            self:SetAlpha(1.0)
            if self.countText then self.countText:Hide() end
            if self.cooldown then CooldownFrame_SetTimer(self.cooldown, 0, 0, 0) end
            return
        end

        -- Standard ActionSlot Buttons (1–6)
        if self.dinoSlotInfo.id == 6 and DinoHUD_GetMountActionSlot then
            self.dinoActionSlot = DinoHUD_GetMountActionSlot()
        end
        local slot = self.dinoActionSlot
        if not slot then return end

        local hasAction = HasAction(slot)
        if hasAction then
            local dmmInfo = DinoHUD_GetActionSlotDMMInfo(slot)
            local texture = (dmmInfo and dmmInfo.texture) or GetActionTexture(slot)
            if self.icon then
                self.icon:SetTexture(texture)
                self.icon:Show()
            end

            local isUsable, notEnoughMana
            if dmmInfo then
                isUsable, notEnoughMana = dmmInfo.isUsable, dmmInfo.notEnoughMana
            else
                isUsable, notEnoughMana = IsUsableAction(slot)
                if self.dinoSlotInfo.id == 6 then
                    isUsable = true
                    notEnoughMana = false
                end

                if IsConsumableAction(slot) then
                    local actionCount = GetActionCount(slot)
                    if actionCount and actionCount == 0 then
                        isUsable = false
                    end
                end
            end

            local inRange = dmmInfo and dmmInfo.inRange or IsActionInRange(slot)
            if inRange == 0 then
                if self.icon then self.icon:SetVertexColor(0.8, 0.1, 0.1) end
            elseif isUsable then
                if self.icon then self.icon:SetVertexColor(1.0, 1.0, 1.0) end
            elseif notEnoughMana then
                if self.icon then self.icon:SetVertexColor(0.3, 0.3, 0.8) end
            else
                if self.icon then self.icon:SetVertexColor(0.4, 0.4, 0.4) end
            end

            if IsConsumableAction(slot) then
                local actionCount = GetActionCount(slot)
                if self.countText then
                    if actionCount and actionCount > 0 then
                        self.countText:SetText(tostring(actionCount))
                        self.countText:Show()
                    else
                        self.countText:SetText("")
                        self.countText:Hide()
                    end
                end
            else
                if self.countText then
                    self.countText:SetText("")
                    self.countText:Hide()
                end
            end

            if self.cooldown then
                local start, duration, enable
                if dmmInfo then
                    start, duration, enable = dmmInfo.cooldownStart, dmmInfo.cooldownDuration, dmmInfo.cooldownEnable
                else
                    start, duration, enable = GetActionCooldown(slot)
                end
                if start and start > 0 and duration and duration > 0 then
                    CooldownFrame_SetTimer(self.cooldown, start, duration, enable)
                else
                    CooldownFrame_SetTimer(self.cooldown, 0, 0, 0)
                end
            end

            self:SetAlpha(1.0)
        else
            if self.icon then
                self.icon:SetTexture(nil)
                self.icon:Hide()
            end
            if self.countText then
                self.countText:SetText("")
                self.countText:Hide()
            end
            if self.cooldown then
                CooldownFrame_SetTimer(self.cooldown, 0, 0, 0)
            end
            self:SetAlpha(0.4)
        end
    end

    -- Drag & Drop
    btn:SetScript("OnDragStart", function()
        if hudLocked then return end
        if this.dinoSlotInfo.id == 8 then return end
        local slot = this.dinoActionSlot
        if slot and HasAction(slot) then
            PickupAction(slot)
            this:UpdateDisplay()
        end
    end)

    btn:SetScript("OnReceiveDrag", function()
        if this.dinoSlotInfo.id == 8 then return end
        local slot = this.dinoActionSlot
        if slot then
            PlaceAction(slot)
            this:UpdateDisplay()
        end
    end)

    btn:SetScript("OnClick", function()
        if this.dinoSlotInfo.id == 5 and hudLocked then
            DinoController_ExecuteXAction()
            this:UpdateDisplay()
            return
        end
        if this.dinoSlotInfo.id == 8 then
            DinoController_ExecuteYAction()
            this:UpdateDisplay()
            return
        end
        if this.dinoSlotInfo.id == 7 then
            local actionInfo = DinoController_GetPrimaryActionInfo and DinoController_GetPrimaryActionInfo()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText((actionInfo and actionInfo.label or "Nahkampf") .. " / Interaktion", 1.0, 1.0, 1.0)
            GameTooltip:Show()
            return
        end

        local slot = this.dinoActionSlot
        if not slot then return end

        if arg1 == "RightButton" and not hudLocked then
            PickupAction(slot)
            ClearCursor()
            this:UpdateDisplay()
        elseif arg1 == "LeftButton" then
            if not hudLocked then
                PlaceAction(slot)
            else
                UseAction(slot)
            end
            this:UpdateDisplay()
        end
    end)

    btn:SetScript("OnEnter", function()
        if this.dinoSlotInfo.id == 8 then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("Target Player (Y)", 1.0, 1.0, 1.0)
            GameTooltip:AddLine("Nimmt dich selbst ins Visier.", 0.8, 0.8, 0.8, 1)
            GameTooltip:Show()
            return
        end

        local slot = this.dinoActionSlot
        if slot and HasAction(slot) then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetAction(slot)
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    btn:UpdateDisplay()
    return btn
end

function DinoHUD_ApplyLayout()
    if not hudFrame or not hudButtons[2] or not hudButtons[4] or not hudButtons[5] or not hudButtons[6] then return end

    local btn2 = hudButtons[2]
    local btn4 = hudButtons[4]
    local btn5 = hudButtons[5]
    local btn6 = hudButtons[6]
    local layout = (DinoControllerDB and DinoControllerDB.hudLayout) or "Unten"
    local bottomLayoutHeight = HUD_SPACING + 2 + HUD_BUTTON_SIZE * 3 + HUD_SPACING * 2 + 2 + HUD_SPACING + HUD_BUTTON_SIZE + HUD_SPACING + 14 + 4

    btn5:ClearAllPoints()
    btn6:ClearAllPoints()

    if layout == "Seitlich" then
        btn5:SetPoint("RIGHT", btn4, "LEFT", -(HUD_SPACING * 2), 0)
        btn6:SetPoint("LEFT", btn2, "RIGHT", HUD_SPACING * 2, 0)
        hudFrame.separator:Hide()
        hudFrame:SetWidth(HUD_BUTTON_SIZE * 4 + HUD_SPACING * 6 + 8)
        hudFrame:SetHeight(HUD_SPACING + 2 + HUD_BUTTON_SIZE * 3 + HUD_SPACING * 3 + 18)
    else
        local xOffset = HUD_BUTTON_SIZE + HUD_SPACING
        btn5:SetPoint("TOP", hudFrame.separator, "BOTTOM", -xOffset, -(HUD_SPACING + 1))
        btn6:SetPoint("TOP", hudFrame.separator, "BOTTOM", xOffset, -(HUD_SPACING + 1))
        hudFrame.separator:Show()
        hudFrame:SetWidth(HUD_BUTTON_SIZE * 3 + HUD_SPACING * 4 + HUD_SPACING * 2 + 8)
        hudFrame:SetHeight(bottomLayoutHeight)
    end
end

-- =========================================================================
-- Haupt-HUD-Frame erstellen
-- =========================================================================

local function CreateHUDFrame()
    if hudFrame then return end

    EnsureHUDDefaults()

    hudFrame = CreateFrame("Frame", "DinoControllerHUDFrame", UIParent)
    hudFrame:SetPoint("CENTER", UIParent, "CENTER", DinoControllerHUDDB.posX, DinoControllerHUDDB.posY)
    hudFrame:SetFrameStrata("BACKGROUND")
    hudFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    hudFrame:SetBackdropColor(0.04, 0.06, 0.10, 0.85)
    hudFrame:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.9)
    hudFrame:EnableMouse(true)
    hudFrame:SetMovable(true)
    hudFrame:RegisterForDrag("LeftButton")
    hudFrame:SetScript("OnDragStart", function()
        if not hudLocked then this:StartMoving() end
    end)
    hudFrame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local cx, cy = this:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            DinoControllerHUDDB.posX = cx - ux
            DinoControllerHUDDB.posY = cy - uy
            this:ClearAllPoints()
            this:SetPoint("CENTER", UIParent, "CENTER", DinoControllerHUDDB.posX, DinoControllerHUDDB.posY)
        end
    end)

    local dpadTop = -HUD_SPACING - 2
    local btn1 = CreateHUDButton(hudFrame, HUD_SLOTS[1], 1)
    btn1:SetPoint("TOP", hudFrame, "TOP", 0, dpadTop)
    hudButtons[1] = btn1

    local btn4 = CreateHUDButton(hudFrame, HUD_SLOTS[4], 4)
    btn4:SetPoint("TOP", btn1, "BOTTOM", -(HUD_BUTTON_SIZE / 2 + HUD_SPACING), -HUD_SPACING)
    hudButtons[4] = btn4

    local btn2 = CreateHUDButton(hudFrame, HUD_SLOTS[2], 2)
    btn2:SetPoint("TOP", btn1, "BOTTOM", (HUD_BUTTON_SIZE / 2 + HUD_SPACING), -HUD_SPACING)
    hudButtons[2] = btn2

    local btn3 = CreateHUDButton(hudFrame, HUD_SLOTS[3], 3)
    btn3:SetPoint("TOP", btn4, "BOTTOM", (HUD_BUTTON_SIZE / 2 + HUD_SPACING), -HUD_SPACING)
    hudButtons[3] = btn3

    local separator = hudFrame:CreateTexture(nil, "ARTWORK")
    separator:SetTexture("Interface\\Buttons\\WHITE8x8")
    separator:SetVertexColor(0.4, 0.65, 0.9, 0.3)
    separator:SetHeight(1)
    separator:SetWidth(HUD_BUTTON_SIZE * 3 + HUD_SPACING * 4)
    separator:SetPoint("TOP", btn3, "BOTTOM", 0, -(HUD_SPACING + 1))
    hudFrame.separator = separator

    -- Bottom row: [ X/Y ] [ empty ] [ B3 ]
    -- Frei belegbare X/Y-Aktion
    local btn5 = CreateHUDButton(hudFrame, HUD_SLOTS[5], 5)
    hudButtons[5] = btn5

    -- B3 = Mount (ActionSlot 14; internal behavior unchanged)
    local btn6 = CreateHUDButton(hudFrame, HUD_SLOTS[6], 6)
    hudButtons[6] = btn6

    -- Hints
    local xHint = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xHint:SetPoint("TOP", btn5, "BOTTOM", 0, -1)
    xHint:SetText("|cffaaaaaaX|r")
    hudFrame.xHint = xHint

    local r3Hint = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r3Hint:SetPoint("TOP", btn6, "BOTTOM", 0, -1)
    r3Hint:SetText("|cffaaaaaaB3|r")
    hudFrame.r3Hint = r3Hint

    DinoHUD_ApplyLayout()

    local lockOverlay = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockOverlay:SetPoint("BOTTOM", hudFrame, "BOTTOM", 0, 2)
    lockOverlay:SetText("|cffff9933UNLOCKED|r")
    lockOverlay:Hide()
    hudFrame.lockOverlay = lockOverlay

    if DinoControllerHUDDB.hudVisible == 1 and (DinoControllerDB == nil or DinoControllerDB.controllerEnabled == 1) then
        hudFrame:Show()
    else
        hudFrame:Hide()
    end

    hudLocked = (DinoControllerHUDDB.hudLocked == 1)
    UpdateHUDLockState()
    DinoHUD_UpdateLabels()
    DinoHUD_UpdateActivePage()
end

-- =========================================================================
-- Lock / Unlock / Show / Hide
-- =========================================================================

function UpdateHUDLockState()
    if not hudFrame then return end

    if hudLocked then
        hudFrame:EnableMouse(false)
        if hudFrame.lockOverlay then hudFrame.lockOverlay:Hide() end
        local i
        for i = 1, 8 do
            if hudButtons[i] then
                hudButtons[i]:EnableMouse(false)
            end
        end
    else
        hudFrame:EnableMouse(true)
        if hudFrame.lockOverlay then hudFrame.lockOverlay:Show() end
        local i
        for i = 1, 8 do
            if hudButtons[i] then
                hudButtons[i]:EnableMouse(true)
            end
        end
    end
end

function DinoHUD_Lock()
    hudLocked = true
    DinoControllerHUDDB.hudLocked = 1
    UpdateHUDLockState()
    HUDPrint("HUD gesperrt.")
end

function DinoHUD_Unlock()
    hudLocked = false
    DinoControllerHUDDB.hudLocked = 0
    UpdateHUDLockState()
    HUDPrint("HUD entsperrt – verschieben und Drag & Drop moeglich.")
end

function DinoHUD_ToggleLock()
    if hudLocked then DinoHUD_Unlock() else DinoHUD_Lock() end
end

function DinoHUD_UpdateVisibility()
    if DinoHUD_UpdateActionbarHighlights then
        DinoHUD_UpdateActionbarHighlights()
    end
    if not hudFrame then return end
    if DinoControllerDB and DinoControllerDB.controllerEnabled == 1 and DinoControllerHUDDB and DinoControllerHUDDB.hudVisible == 1 then
        hudFrame:Show()
    else
        hudFrame:Hide()
    end
end

function DinoHUD_Show()
    hudVisible = true
    DinoControllerHUDDB.hudVisible = 1
    DinoHUD_UpdateVisibility()
    HUDPrint("HUD eingeblendet.")
end

function DinoHUD_Hide()
    hudVisible = false
    DinoControllerHUDDB.hudVisible = 0
    DinoHUD_UpdateVisibility()
    HUDPrint("HUD ausgeblendet.")
end

function DinoHUD_GetMountActionSlot()
    return 14
end

function DinoHUD_UseMount()
    if DinoController_IsUIModeActive and DinoController_IsUIModeActive() then return end
    DinoHUD_TriggerFlashSlot14()
    local slot = DinoHUD_GetMountActionSlot()
    if slot and HasAction(slot) then
        UseAction(slot)
    end
end

function DinoHUD_UseAction(slotIndex)
    if DinoController_IsUIModeActive and DinoController_IsUIModeActive() then return end
    if slotIndex < 1 or slotIndex > 4 then
        if slotIndex == 6 then
            DinoHUD_UseMount()
        end
        return
    end

    local offset = DinoHUD_GetPageOffset()
    local slot = slotIndex + offset
    if slot and slot >= 1 and slot <= 12 and HasAction(slot) then
        UseAction(slot)
    end
end

function DinoHUD_Action1() DinoHUD_UseAction(1) end
function DinoHUD_Action2() DinoHUD_UseAction(2) end
function DinoHUD_Action3() DinoHUD_UseAction(3) end
function DinoHUD_Action4() DinoHUD_UseAction(4) end

-- =========================================================================
-- Update-Loop & Events
-- =========================================================================

local hudUpdateFrame = CreateFrame("Frame", "DinoHUDUpdateFrame")
hudUpdateFrame:SetScript("OnUpdate", function()
    hudUpdateElapsed = hudUpdateElapsed + arg1
    if hudUpdateElapsed < HUD_UPDATE_INTERVAL then return end
    hudUpdateElapsed = 0

    local now = GetTime()
    local clearedFlash = nil
    if flashSlot13Until and now >= flashSlot13Until then
        flashSlot13Until = nil
        clearedFlash = 1
    end
    if flashSlot14Until and now >= flashSlot14Until then
        flashSlot14Until = nil
        clearedFlash = 1
    end

    if clearedFlash and DinoHUD_UpdateActionbarHighlights then
        DinoHUD_UpdateActionbarHighlights()
    end

    UpdateAllButtons()
end)

hudUpdateFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
hudUpdateFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
hudUpdateFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
hudUpdateFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
hudUpdateFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
hudUpdateFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
hudUpdateFrame:RegisterEvent("BAG_UPDATE")
hudUpdateFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
hudUpdateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
hudUpdateFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
hudUpdateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hudUpdateFrame:RegisterEvent("UI_SCALE_CHANGED")

hudUpdateFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        if not hudFrame then
            CreateHUDFrame()
        end
        EnsureHUDDefaults()
        if hudFrame then
            hudFrame:ClearAllPoints()
            hudFrame:SetPoint("CENTER", UIParent, "CENTER",
                DinoControllerHUDDB.posX or 0,
                DinoControllerHUDDB.posY or -200)
            if DinoControllerHUDDB.hudVisible == 1 and (DinoControllerDB == nil or DinoControllerDB.controllerEnabled == 1) then
                hudFrame:Show()
            else
                hudFrame:Hide()
            end
        end
        DinoHUD_UpdateActivePage()
    end
    if DinoHUD_UpdateActionbarHighlights then
        DinoHUD_UpdateActionbarHighlights()
    end
    UpdateAllButtons()
end)

-- =========================================================================
-- Integration: Bindings
-- =========================================================================

function DinoHUD_InstallWorldBindings()
    local mappings = DinoControllerBridgeConfig and DinoControllerBridgeConfig.ButtonMappings or {}

    local dpadUp = DinoController_NormalizeBindingKey(mappings.DPadUp)
    local dpadRight = DinoController_NormalizeBindingKey(mappings.DPadRight)
    local dpadDown = DinoController_NormalizeBindingKey(mappings.DPadDown)
    local dpadLeft = DinoController_NormalizeBindingKey(mappings.DPadLeft)

    if dpadUp then SetBinding(dpadUp, "DINOHUD_ACTION1") end
    if dpadRight then SetBinding(dpadRight, "DINOHUD_ACTION2") end
    if dpadDown then SetBinding(dpadDown, "DINOHUD_ACTION3") end
    if dpadLeft then SetBinding(dpadLeft, "DINOHUD_ACTION4") end

    local xKey = DinoController_NormalizeBindingKey(mappings.X)
    if xKey then SetBinding(xKey, "DINOCONTROLLER_X_ACTION") end

    local r3Key = DinoController_NormalizeBindingKey(mappings.R3)
    if r3Key then SetBinding(r3Key, "DINOHUD_MOUNT") end

    local l2Key = DinoController_NormalizeBindingKey(mappings.L2)
    if l2Key then SetBinding(l2Key, "DINOHUD_L2_MODIFIER") end

    local r2Key = DinoController_NormalizeBindingKey(mappings.R2)
    if r2Key then SetBinding(r2Key, "DINOHUD_R2_MODIFIER") end

    SaveBindings(GetCurrentBindingSet())
end

local originalSlashHandler = SlashCmdList["DINOCONTROLLER"]

SlashCmdList["DINOCONTROLLER"] = function(message)
    local text = string.lower(message or "")
    local _, _, command, value = string.find(text, "^(%S*)%s*(%S*)")

    if command == "lock" then
        DinoHUD_Lock()
    elseif command == "unlock" then
        DinoHUD_Unlock()
    elseif command == "hud" then
        if value == "on" or value == "an" then
            DinoHUD_Show()
        elseif value == "off" or value == "aus" then
            DinoHUD_Hide()
        else
            if hudVisible then DinoHUD_Hide() else DinoHUD_Show() end
        end
    else
        if originalSlashHandler then
            originalSlashHandler(message)
        end
    end
end
