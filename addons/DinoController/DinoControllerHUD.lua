-- DinoControllerHUD.lua – Controller-HUD mit 12-Slot Actionbar & ClassMode
-- Vanilla 1.12.1 stellt 120 ActionSlots bereit.
-- Die 4 D-Pad-Slots bedienen die untere WoW-Actionbar (Slots 1–12):
--   Ohne Modifier: Slots 1–4
--   L2 gehalten:   Slots 5–8
--   R2 gehalten:   Slots 9–12
-- Slot 5 (X):      Klassenmodus (Haltung / Form / Stealth)
-- Slot 6 (R3):     Mount (ActionSlot 78)

DinoControllerHUDDB = DinoControllerHUDDB or {}

local HUD_SLOTS = {
    { id = 1, name = "DPadUp",    actionSlot = 1,  label = "UP", arrow = "↑" },
    { id = 2, name = "DPadRight", actionSlot = 2,  label = "RT", arrow = "→" },
    { id = 3, name = "DPadDown",  actionSlot = 3,  label = "DN", arrow = "↓" },
    { id = 4, name = "DPadLeft",  actionSlot = 4,  label = "LT", arrow = "←" },
    { id = 5, name = "ClassMode", actionSlot = nil, label = "X",  arrow = nil },
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

    if hudFrame and hudFrame.xHint then
        local actionType = DinoControllerDB and DinoControllerDB.xActionType or "ClassMode"
        if actionType == "Action" then
            local actSlot = 13
            hudFrame.xHint:SetText("|cffaaaaaaSlot " .. actSlot .. "|r")
        else
            hudFrame.xHint:SetText("|cffaaaaaaStance|r")
        end
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

function DinoHUD_GetPageOffset()
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

-- =========================================================================
-- Klassenmodus (Stance / Form / Stealth)
-- =========================================================================

function DinoHUD_CycleClassStance()
    if DinoController_IsUIModeActive and DinoController_IsUIModeActive() then return end
    local numForms = GetNumShapeshiftForms()
    if not numForms or numForms == 0 then return end

    local activeIndex = 0
    local i
    for i = 1, numForms do
        local texture, name, isActive, isCastable = GetShapeshiftFormInfo(i)
        if isActive then
            activeIndex = i
            break
        end
    end

    if numForms == 1 then
        CastShapeshiftForm(1)
    else
        local nextIndex = activeIndex + 1
        if nextIndex > numForms then
            if activeIndex == numForms then
                CastShapeshiftForm(activeIndex)
                return
            end
            nextIndex = 1
        end
        CastShapeshiftForm(nextIndex)
    end
end

-- =========================================================================
-- Einzelnen HUD-Button erstellen
-- =========================================================================

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
    -- UpdateDisplay: Slot 1–4 & 6 (ActionSlot) vs Slot 5 (ClassMode)
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

        if self.dinoSlotInfo.id == 5 then
            -- X Aktion Button
            local actionType = DinoControllerDB and DinoControllerDB.xActionType or "ClassMode"

            if actionType == "Action" then
                local actSlot = 13
                local hasAction = HasAction(actSlot)
                if hasAction then
                    local texture = GetActionTexture(actSlot)
                    if self.icon then
                        self.icon:SetTexture(texture)
                        self.icon:Show()
                    end

                    local isUsable, notEnoughMana = IsUsableAction(actSlot)
                    if IsConsumableAction(actSlot) then
                        local actionCount = GetActionCount(actSlot)
                        if actionCount and actionCount == 0 then
                            isUsable = false
                        end
                    end

                    if isUsable then
                        if self.icon then self.icon:SetVertexColor(1.0, 1.0, 1.0) end
                    elseif notEnoughMana then
                        if self.icon then self.icon:SetVertexColor(0.3, 0.3, 0.8) end
                    else
                        if self.icon then self.icon:SetVertexColor(0.4, 0.4, 0.4) end
                    end
                    self:SetAlpha(1.0)

                    if self.cooldown then
                        local start, duration, enable = GetActionCooldown(actSlot)
                        if start and start > 0 and duration and duration > 0 then
                            CooldownFrame_SetTimer(self.cooldown, start, duration, enable)
                        else
                            CooldownFrame_SetTimer(self.cooldown, 0, 0, 0)
                        end
                    end
                else
                    if self.icon then
                        self.icon:SetTexture(nil)
                        self.icon:Hide()
                    end
                    self:SetAlpha(0.4)
                end
            else
                -- ClassMode
                local numForms = GetNumShapeshiftForms()
                if numForms and numForms > 0 then
                    local activeIndex = 0
                    local activeTexture = nil
                    local i
                    for i = 1, numForms do
                        local texture, name, isActive = GetShapeshiftFormInfo(i)
                        if isActive then
                            activeIndex = i
                            activeTexture = texture
                            break
                        end
                    end
                    if activeIndex > 0 and activeTexture then
                        if self.icon then
                            self.icon:SetTexture(activeTexture)
                            self.icon:Show()
                            self.icon:SetVertexColor(1.0, 1.0, 1.0)
                        end
                        self:SetAlpha(1.0)
                    else
                        local texture = GetShapeshiftFormInfo(1)
                        if texture and self.icon then
                            self.icon:SetTexture(texture)
                            self.icon:Show()
                            self.icon:SetVertexColor(1.0, 1.0, 1.0)
                        else
                            if self.icon then self.icon:Hide() end
                        end
                        self:SetAlpha(1.0)
                    end
                else
                    if self.icon then
                        self.icon:SetTexture(nil)
                        self.icon:Hide()
                    end
                    self:SetAlpha(0.4)
                end
            end
            if self.countText then self.countText:Hide() end
            if self.cooldown then CooldownFrame_SetTimer(self.cooldown, 0, 0, 0) end
            return
        end

        if self.dinoSlotInfo.id == 7 then
            -- A-Taste: AutoHit / Interact
            if self.icon then
                self.icon:SetTexture("Interface\\Icons\\Ability_MeleeDamage")
                self.icon:Show()
                self.icon:SetVertexColor(1.0, 1.0, 1.0)
            end
            self:SetAlpha(1.0)
            if self.countText then self.countText:Hide() end
            if self.cooldown then CooldownFrame_SetTimer(self.cooldown, 0, 0, 0) end
            return
        end

        -- Standard ActionSlot Buttons (1–4, 6)
        if self.dinoSlotInfo.id == 6 and DinoHUD_GetMountActionSlot then
            self.dinoActionSlot = DinoHUD_GetMountActionSlot()
        end
        local slot = self.dinoActionSlot
        if not slot then return end

        local hasAction = HasAction(slot)
        if hasAction then
            local texture = GetActionTexture(slot)
            if self.icon then
                self.icon:SetTexture(texture)
                self.icon:Show()
            end

            local isUsable, notEnoughMana = IsUsableAction(slot)
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

            if isUsable then
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
                local start, duration, enable = GetActionCooldown(slot)
                if start and start > 0 and duration and duration > 0 then
                    CooldownFrame_SetTimer(self.cooldown, start, duration, enable)
                else
                    CooldownFrame_SetTimer(self.cooldown, 0, 0, 0)
                end
            end

            if IsActionInRange(slot) == 0 then
                if self.icon then self.icon:SetVertexColor(0.8, 0.1, 0.1) end
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
        if this.dinoSlotInfo.id == 5 or this.dinoSlotInfo.id == 8 then return end
        local slot = this.dinoActionSlot
        if slot and HasAction(slot) then
            PickupAction(slot)
            this:UpdateDisplay()
        end
    end)

    btn:SetScript("OnReceiveDrag", function()
        if this.dinoSlotInfo.id == 5 or this.dinoSlotInfo.id == 8 then return end
        local slot = this.dinoActionSlot
        if slot then
            PlaceAction(slot)
            this:UpdateDisplay()
        end
    end)

    btn:SetScript("OnClick", function()
        if this.dinoSlotInfo.id == 5 then
            DinoController_ExecuteXAction()
            this:UpdateDisplay()
            return
        end
        if this.dinoSlotInfo.id == 8 then
            DinoController_ExecuteYAction()
            this:UpdateDisplay()
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
        if this.dinoSlotInfo.id == 5 then
            local actionType = DinoControllerDB and DinoControllerDB.xActionType or "ClassMode"
            if actionType == "ClassMode" then
                local numForms = GetNumShapeshiftForms()
                if numForms and numForms > 0 then
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Klassenmodus (X)", 1.0, 1.0, 1.0)
                    GameTooltip:AddLine("Schaltet durch Haltungen / Formen / Stealth.", 0.8, 0.8, 0.8, 1)
                    GameTooltip:Show()
                end
            elseif actionType == "Action" then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetAction(13)
                GameTooltip:Show()
            end
            return
        end
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

    -- Bottom row: [ X ] [ A ] [ R3 ]
    local xOffset = HUD_BUTTON_SIZE + HUD_SPACING

    -- X = ClassMode or Custom 13
    local btn5 = CreateHUDButton(hudFrame, HUD_SLOTS[5], 5)
    btn5:SetPoint("TOP", separator, "BOTTOM", -xOffset, -(HUD_SPACING + 1))
    hudButtons[5] = btn5

    -- A = Confirm / Action
    local btn7 = CreateHUDButton(hudFrame, HUD_SLOTS[7], 7)
    btn7:SetPoint("TOP", separator, "BOTTOM", 0, -(HUD_SPACING + 1))
    if btn7.bg then btn7.bg:SetVertexColor(0.15, 0.75, 0.3, 0.85) end
    if btn7.border then btn7.border:SetVertexColor(0.3, 1.0, 0.45, 0.9) end
    hudButtons[7] = btn7

    -- R3 = Mount (Slot 14)
    local btn6 = CreateHUDButton(hudFrame, HUD_SLOTS[6], 6)
    btn6:SetPoint("TOP", separator, "BOTTOM", xOffset, -(HUD_SPACING + 1))
    hudButtons[6] = btn6

    -- Hints
    local aHint = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    aHint:SetPoint("TOP", btn7, "BOTTOM", 0, -1)
    aHint:SetText("|cff55ff77Aktion|r")
    hudFrame.aHint = aHint

    local xHint = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    xHint:SetPoint("TOP", btn5, "BOTTOM", 0, -1)
    xHint:SetText("|cffaaaaaaStance|r")
    hudFrame.xHint = xHint

    local r3Hint = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r3Hint:SetPoint("TOP", btn6, "BOTTOM", 0, -1)
    r3Hint:SetText("|cffaaaaaaSlot 14|r")
    hudFrame.r3Hint = r3Hint

    local totalHeight = HUD_SPACING + 2 + HUD_BUTTON_SIZE * 3 + HUD_SPACING * 2 + 2 + HUD_SPACING + HUD_BUTTON_SIZE + HUD_SPACING + 14 + 4
    local totalWidth = HUD_BUTTON_SIZE * 3 + HUD_SPACING * 4 + HUD_SPACING * 2 + 8
    hudFrame:SetHeight(totalHeight)
    hudFrame:SetWidth(totalWidth)

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
    UpdateAllButtons()
end)

hudUpdateFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
hudUpdateFrame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
hudUpdateFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
hudUpdateFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
hudUpdateFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
hudUpdateFrame:RegisterEvent("BAG_UPDATE")
hudUpdateFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
hudUpdateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
hudUpdateFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
hudUpdateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

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
    if xKey then SetBinding(xKey, "DINOHUD_CLASSMODE") end

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
