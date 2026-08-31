-- DinoController Phase 2.5 - aufloesungsunabhaengige Controller-Navigation
-- fuer originale Vanilla-Frames. Es werden ausschliesslich echte, sichtbare
-- WoW-Buttons aus FrameXML angesprochen; feste Bildschirmkoordinaten gibt es
-- nicht.

local UI_SCAN_INTERVAL = 0.08

local state = {
    active = nil,
    context = nil,
    elements = {},
    index = 1,
    nextScan = 0,
    temporaryBindings = nil
}

local function UIPrint(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7fc8ffDinoController:|r " .. message)
    end
end

local function Visible(name)
    local frame = getglobal(name)
    return frame and frame.IsVisible and frame:IsVisible()
end

local function UsableButton(button)
    if not button or not button.IsVisible or not button:IsVisible() then return nil end
    if button.IsEnabled then
        local enabled = button:IsEnabled()
        if enabled == nil or enabled == 0 then return nil end
    end
    if not button.GetCenter then return nil end
    local x, y = button:GetCenter()
    if not x or not y then return nil end
    return 1
end

local function AddButton(elements, name, mouseButton, action)
    local button = getglobal(name)
    if not UsableButton(button) then return end
    table.insert(elements, {
        key = name,
        frame = button,
        mouseButton = mouseButton or "LeftButton",
        action = action
    })
end

local function AddRange(elements, prefix, first, last, suffix, mouseButton)
    local index
    for index = first, last do
        AddButton(elements, prefix .. index .. (suffix or ""), mouseButton)
    end
end

local function AddContainers(elements, mouseButton)
    local frameIndex, itemIndex
    local count = NUM_CONTAINER_FRAMES or 12
    for frameIndex = 1, count do
        if Visible("ContainerFrame" .. frameIndex) then
            for itemIndex = 1, 20 do
                AddButton(elements, "ContainerFrame" .. frameIndex .. "Item" .. itemIndex,
                    mouseButton or "RightButton")
            end
            AddButton(elements, "ContainerFrame" .. frameIndex .. "CloseButton")
        end
    end
end

local function AddMerchant(elements)
    AddRange(elements, "MerchantItem", 1, 12, "ItemButton", "RightButton")
    AddButton(elements, "MerchantBuyBackItemItemButton", "RightButton")
    AddButton(elements, "MerchantPrevPageButton")
    AddButton(elements, "MerchantNextPageButton")
    AddButton(elements, "MerchantRepairItemButton")
    AddButton(elements, "MerchantRepairAllButton")
    AddButton(elements, "MerchantFrameCloseButton")
    AddContainers(elements, "RightButton")
end

local function ResolveLootSlot(button)
    if not button then return nil end
    local slot = button.slot
    if not slot then
        local id = button:GetID()
        if id and id > 0 then
            slot = ((LootFrame.page or 1) - 1) * (LOOTFRAME_NUMBUTTONS or 4) + id
        end
    end
    return slot
end

local function ActivateLootButton(button)
    if not button or not button:IsVisible() then return nil end
    local slot = ResolveLootSlot(button)
    if not slot or slot < 1 or slot > GetNumLootItems() then return nil end
    if not LootSlotIsItem(slot) and not LootSlotIsCoin(slot) then return nil end

    -- Der originale Vanilla-OnClick-Pfad merkt sich Button und Slot, bevor
    -- LootSlot ausgefuehrt wird. Diesen Zustand setzen wir explizit, damit
    -- Controller-Confirm exakt denselben markierten Slot aktiviert.
    button.slot = slot
    LootFrame.selectedLootButton = button:GetName()
    LootFrame.selectedSlot = slot

    local ok, message = pcall(LootSlot, slot)
    if not ok then
        UIPrint("Loot-Slot " .. tostring(slot) .. " konnte nicht genommen werden: " .. tostring(message))
        return nil
    end
    return 1
end

local function AddLoot(elements)
    local index
    for index = 1, 4 do
        local name = "LootButton" .. index
        local button = getglobal(name)
        if UsableButton(button) then
            local lootButton = button
            AddButton(elements, name, "LeftButton", function()
                ActivateLootButton(lootButton)
            end)
        end
    end
    AddButton(elements, "LootFrameUpButton")
    AddButton(elements, "LootFrameDownButton")
    AddButton(elements, "LootCloseButton")
end

local function AddGossip(elements)
    AddRange(elements, "GossipTitleButton", 1, 16)
    AddButton(elements, "GossipFrameGreetingGoodbyeButton")
    AddButton(elements, "GossipFrameCloseButton")
end

local function AddQuest(elements)
    if Visible("QuestFrameRewardPanel") then
        local choices = GetNumQuestChoices() or 0
        AddRange(elements, "QuestRewardItem", 1, choices)
        AddButton(elements, "QuestFrameCompleteQuestButton")
        AddButton(elements, "QuestFrameCancelButton")
    elseif Visible("QuestFrameProgressPanel") then
        AddButton(elements, "QuestFrameCompleteButton")
        AddButton(elements, "QuestFrameGoodbyeButton")
    elseif Visible("QuestFrameDetailPanel") then
        AddButton(elements, "QuestFrameAcceptButton")
        AddButton(elements, "QuestFrameDeclineButton")
    elseif Visible("QuestFrameGreetingPanel") then
        AddRange(elements, "QuestTitleButton", 1, 32)
        AddButton(elements, "QuestFrameGreetingGoodbyeButton")
    end
    AddButton(elements, "QuestFrameCloseButton")
end

local function AddTrainer(elements)
    AddRange(elements, "ClassTrainerSkill", 1, 11)
    AddButton(elements, "ClassTrainerAvailableButton")
    AddButton(elements, "ClassTrainerUnavailableButton")
    AddButton(elements, "ClassTrainerUsedButton")
    AddButton(elements, "ClassTrainerTrainButton")
    AddButton(elements, "ClassTrainerCancelButton")
    AddButton(elements, "ClassTrainerFrameCloseButton")
end

local function AddBank(elements)
    AddRange(elements, "BankFrameItem", 1, 24, nil, "RightButton")
    AddRange(elements, "BankFrameBag", 1, 6)
    AddButton(elements, "BankFramePurchaseInfoPurchaseButton")
    AddButton(elements, "BankCloseButton")
    AddContainers(elements, "RightButton")
end

local function AddMail(elements)
    if Visible("OpenMailFrame") then
        AddButton(elements, "OpenMailLetterButton")
        AddButton(elements, "OpenMailPackageButton")
        AddButton(elements, "OpenMailMoneyButton")
        AddButton(elements, "OpenMailReplyButton")
        AddButton(elements, "OpenMailDeleteButton")
        AddButton(elements, "OpenMailCancelButton")
        AddButton(elements, "OpenMailCloseButton")
    elseif Visible("InboxFrame") then
        AddRange(elements, "MailItem", 1, 7, "Button")
        AddButton(elements, "InboxPrevPageButton")
        AddButton(elements, "InboxNextPageButton")
        AddButton(elements, "MailFrameTab1")
        AddButton(elements, "MailFrameTab2")
        AddButton(elements, "InboxCloseButton")
    elseif Visible("SendMailFrame") then
        AddButton(elements, "SendMailPackageButton")
        AddButton(elements, "SendMailSendMoneyButton")
        AddButton(elements, "SendMailCODButton")
        AddButton(elements, "SendMailStationeryButton")
        AddButton(elements, "SendMailMailButton")
        AddButton(elements, "SendMailCancelButton")
        AddButton(elements, "MailFrameTab1")
        AddButton(elements, "MailFrameTab2")
        AddButton(elements, "InboxCloseButton")
    end
end

local characterSlots = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
    "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
    "CharacterTabardSlot", "CharacterWristSlot", "CharacterHandsSlot",
    "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot",
    "CharacterTrinket1Slot", "CharacterMainHandSlot",
    "CharacterSecondaryHandSlot", "CharacterRangedSlot", "CharacterAmmoSlot"
}

local function AddCharacter(elements)
    local index
    for index = 1, table.getn(characterSlots) do
        AddButton(elements, characterSlots[index])
    end
    AddRange(elements, "CharacterFrameTab", 1, 4)
    AddButton(elements, "CharacterFrameCloseButton")
    AddContainers(elements, "RightButton")
end

local function AddQuestLog(elements)
    AddRange(elements, "QuestLogTitle", 1, 6)
    AddRange(elements, "QuestLogItem", 1, 10)
    AddButton(elements, "QuestLogCollapseAllButton")
    AddButton(elements, "QuestFramePushQuestButton")
    AddButton(elements, "QuestLogFrameAbandonButton")
    AddButton(elements, "QuestFrameExitButton")
    AddButton(elements, "QuestLogFrameCloseButton")
end

local function AddStaticPopup(elements)
    local popupIndex, buttonIndex
    for popupIndex = 1, 4 do
        if Visible("StaticPopup" .. popupIndex) then
            for buttonIndex = 1, 3 do
                AddButton(elements, "StaticPopup" .. popupIndex .. "Button" .. buttonIndex)
            end
            return
        end
    end
end

local function BuildElements()
    local elements = {}
    local context = nil

    local popupIndex
    for popupIndex = 1, 4 do
        if Visible("StaticPopup" .. popupIndex) then
            context = "popup"
            AddStaticPopup(elements)
            return context, elements
        end
    end

    if Visible("QuestFrame") then
        context = "quest"
        AddQuest(elements)
    elseif Visible("GossipFrame") then
        context = "gossip"
        AddGossip(elements)
    elseif Visible("MerchantFrame") then
        context = "merchant"
        AddMerchant(elements)
    elseif Visible("LootFrame") then
        context = "loot"
        AddLoot(elements)
    elseif Visible("ClassTrainerFrame") then
        context = "trainer"
        AddTrainer(elements)
    elseif Visible("BankFrame") then
        context = "bank"
        AddBank(elements)
    elseif Visible("OpenMailFrame") or Visible("MailFrame") then
        context = "mail"
        AddMail(elements)
    elseif Visible("QuestLogFrame") then
        context = "questlog"
        AddQuestLog(elements)
    elseif Visible("CharacterFrame") then
        context = "character"
        AddCharacter(elements)
    else
        local frameIndex
        for frameIndex = 1, (NUM_CONTAINER_FRAMES or 12) do
            if Visible("ContainerFrame" .. frameIndex) then
                context = "bags"
                AddContainers(elements, "RightButton")
                break
            end
        end
    end

    return context, elements
end

local highlight = CreateFrame("Frame", "DinoControllerUIHighlight", UIParent)
highlight:SetFrameStrata("TOOLTIP")
highlight:EnableMouse(false)

local highlightTop = highlight:CreateTexture(nil, "OVERLAY")
highlightTop:SetTexture("Interface\\Buttons\\WHITE8x8")
highlightTop:SetVertexColor(0.35, 0.82, 1.0, 0.95)
highlightTop:SetHeight(2)
highlightTop:SetPoint("TOPLEFT", highlight, "TOPLEFT", 0, 0)
highlightTop:SetPoint("TOPRIGHT", highlight, "TOPRIGHT", 0, 0)

local highlightBottom = highlight:CreateTexture(nil, "OVERLAY")
highlightBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
highlightBottom:SetVertexColor(0.35, 0.82, 1.0, 0.95)
highlightBottom:SetHeight(2)
highlightBottom:SetPoint("BOTTOMLEFT", highlight, "BOTTOMLEFT", 0, 0)
highlightBottom:SetPoint("BOTTOMRIGHT", highlight, "BOTTOMRIGHT", 0, 0)

local highlightLeft = highlight:CreateTexture(nil, "OVERLAY")
highlightLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
highlightLeft:SetVertexColor(0.35, 0.82, 1.0, 0.95)
highlightLeft:SetWidth(2)
highlightLeft:SetPoint("TOPLEFT", highlight, "TOPLEFT", 0, 0)
highlightLeft:SetPoint("BOTTOMLEFT", highlight, "BOTTOMLEFT", 0, 0)

local highlightRight = highlight:CreateTexture(nil, "OVERLAY")
highlightRight:SetTexture("Interface\\Buttons\\WHITE8x8")
highlightRight:SetVertexColor(0.35, 0.82, 1.0, 0.95)
highlightRight:SetWidth(2)
highlightRight:SetPoint("TOPRIGHT", highlight, "TOPRIGHT", 0, 0)
highlightRight:SetPoint("BOTTOMRIGHT", highlight, "BOTTOMRIGHT", 0, 0)
highlight:Hide()

local function TriggerOnLeave(element)
    if not element or not element.frame then return end
    local f = element.frame
    local script = f.GetScript and f:GetScript("OnLeave")
    if script then
        local oldThis = this
        this = f
        pcall(script)
        this = oldThis
    else
        GameTooltip:Hide()
    end
end

local function TriggerOnEnter(element)
    if not element or not element.frame then return end
    local f = element.frame
    local script = f.GetScript and f:GetScript("OnEnter")
    if script then
        GameTooltip:Hide()
        local oldThis = this
        this = f
        pcall(script)
        this = oldThis
    end
end

local function UpdateHighlight()
    local element = state.elements[state.index]
    if not state.active or not element or not UsableButton(element.frame) then
        if state.tooltipElement then
            TriggerOnLeave(state.tooltipElement)
            state.tooltipElement = nil
        end
        highlight:Hide()
        return
    end

    if state.tooltipElement ~= element then
        if state.tooltipElement then
            TriggerOnLeave(state.tooltipElement)
        end
        state.tooltipElement = element
        TriggerOnEnter(element)
    end

    highlight:ClearAllPoints()
    highlight:SetPoint("TOPLEFT", element.frame, "TOPLEFT", -3, 3)
    highlight:SetPoint("BOTTOMRIGHT", element.frame, "BOTTOMRIGHT", 3, -3)
    highlight:Show()

    if state.context == "loot" and LootFrame then
        -- Lua kann den Windows-Cursor in Vanilla nicht bewegen. Deshalb wird
        -- der aktuell markierte Originalbutton exakt unter die Mitte von
        -- UIParent gelegt. UIParent:GetCenter() benutzt denselben skalierten
        -- Koordinatenraum wie Frame:GetCenter() und funktioniert daher auch
        -- bei abweichender UI-Skalierung.
        local buttonX, buttonY = element.frame:GetCenter()
        local rootX, rootY = UIParent:GetCenter()
        local frameLeft, frameBottom = LootFrame:GetLeft(), LootFrame:GetBottom()
        if buttonX and buttonY and rootX and rootY and frameLeft and frameBottom then
            LootFrame:ClearAllPoints()
            LootFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                frameLeft + rootX - buttonX, frameBottom + rootY - buttonY)
        end
    end

end

local function NormalizeBindingKey(key)
    if DinoController_NormalizeBindingKey then
        return DinoController_NormalizeBindingKey(key)
    end
    return key
end

local function SaveAndBind(key, command)
    key = NormalizeBindingKey(key)
    if not key then return end
    if state.temporaryBindings[key] == nil then
        state.temporaryBindings[key] = GetBindingAction(key) or ""
    end
    SetBinding(key, command)
end

local function EnterUIMode()
    if state.active then return end
    if DinoControllerDB then
        if DinoControllerDB.controllerEnabled == 0 or DinoControllerDB.uiEnabled == 0 then
            return
        end
    end
    state.active = 1
    state.temporaryBindings = {}
    local mappings = DinoControllerBridgeConfig.ButtonMappings or {}
    SaveAndBind(mappings.DPadUp, "DINOCONTROLLER_UI_UP")
    SaveAndBind(mappings.DPadDown, "DINOCONTROLLER_UI_DOWN")
    SaveAndBind(mappings.DPadLeft, "DINOCONTROLLER_UI_LEFT")
    SaveAndBind(mappings.DPadRight, "DINOCONTROLLER_UI_RIGHT")
    -- In Xbox layout (swapAB=0), Bottom (NUMPAD0) is Confirm, Right (NUMPAD9) is Cancel.
    -- In Nintendo layout (swapAB=1), Right (NUMPAD9) is Confirm, Bottom (NUMPAD0) is Cancel.
    if DinoControllerDB and DinoControllerDB.swapAB == 1 then
        SaveAndBind("NUMPAD9", "DINOCONTROLLER_UI_ACTIVATE")
        SaveAndBind("NUMPAD0", "DINOCONTROLLER_UI_CANCEL")
    else
        SaveAndBind("NUMPAD0", "DINOCONTROLLER_UI_ACTIVATE")
        SaveAndBind("NUMPAD9", "DINOCONTROLLER_UI_CANCEL")
    end
    if DinoController_SetUIMode then DinoController_SetUIMode(1) end
end

local function LeaveUIMode()
    if not state.active then return end
    if state.tooltipElement then
        TriggerOnLeave(state.tooltipElement)
        state.tooltipElement = nil
    end
    GameTooltip:Hide()

    local key, action
    for key, action in pairs(state.temporaryBindings or {}) do
        if action and action ~= "" then SetBinding(key, action) else SetBinding(key) end
    end
    state.temporaryBindings = nil
    state.active = nil
    state.context = nil
    state.elements = {}
    state.index = 1
    highlight:Hide()
    if DinoController_SetUIMode then DinoController_SetUIMode(nil) end
    if DinoController_ApplyButtonLayout then DinoController_ApplyButtonLayout(1) end
end

function DinoController_LeaveUIMode()
    LeaveUIMode()
end

function DinoController_IsUIModeActive()
    return (state and state.active == 1)
end

local function RefreshElements()
    if DinoControllerDB then
        if DinoControllerDB.controllerEnabled == 0 or DinoControllerDB.uiEnabled == 0 then
            if state.active then LeaveUIMode() end
            return
        end
    end

    local oldContext = state.context
    local oldIndex = state.index
    local oldElement = state.elements[oldIndex]
    local oldKey = oldElement and oldElement.key
    local context, elements = BuildElements()

    if not context or table.getn(elements) == 0 then
        LeaveUIMode()
        return
    end

    state.context = context
    state.elements = elements
    if not state.active then EnterUIMode() end

    if context ~= oldContext then
        state.index = 1
    else
        local found = nil
        local index
        if oldKey then
            for index = 1, table.getn(elements) do
                if elements[index].key == oldKey then found = index; break end
            end
        end
        if found then
            state.index = found
        elseif state.pendingLootIndex then
            state.index = state.pendingLootIndex
            state.pendingLootIndex = nil
            if state.index > table.getn(elements) then
                state.index = table.getn(elements)
            end
        elseif oldIndex > table.getn(elements) then
            state.index = table.getn(elements)
        else
            state.index = oldIndex
        end
        if state.index < 1 then state.index = 1 end
    end
    UpdateHighlight()
end

local function MoveSpatial(dir)
    local curElem = state.elements[state.index]
    if not curElem or not curElem.frame then return end
    local curX, curY = curElem.frame:GetCenter()
    if not curX or not curY then return end

    local bestIdx = nil
    local bestDist = 999999
    local i

    for i = 1, table.getn(state.elements) do
        if i ~= state.index then
            local elem = state.elements[i]
            if elem and elem.frame and UsableButton(elem.frame) then
                local tX, tY = elem.frame:GetCenter()
                if tX and tY then
                    local dx = tX - curX
                    local dy = tY - curY
                    local valid = false

                    if dir == "UP" and dy > 3 then
                        valid = true
                    elseif dir == "DOWN" and dy < -3 then
                        valid = true
                    elseif dir == "LEFT" and dx < -3 then
                        valid = true
                    elseif dir == "RIGHT" and dx > 3 then
                        valid = true
                    end

                    if valid then
                        local dist
                        if dir == "UP" or dir == "DOWN" then
                            dist = math.abs(dy) + math.abs(dx) * 2.0
                        else
                            dist = math.abs(dx) + math.abs(dy) * 2.0
                        end
                        if dist < bestDist then
                            bestDist = dist
                            bestIdx = i
                        end
                    end
                end
            end
        end
    end

    if bestIdx then
        state.index = bestIdx
        UpdateHighlight()
    end
end

function DinoController_UIMoveDir(dir)
    if not state.active then
        RefreshElements()
    end
    if not state.elements or table.getn(state.elements) == 0 then return end
    MoveSpatial(dir)
end

function DinoController_UIMove(delta)
    RefreshElements()
    if not state.active then return end
    local count = table.getn(state.elements)
    if count == 0 then return end
    state.index = state.index + delta
    if state.index < 1 then state.index = count end
    if state.index > count then state.index = 1 end
    UpdateHighlight()
end

function DinoController_UIActivate()
    if Visible("LootFrame") then
        if not state.elements or table.getn(state.elements) == 0 then
            RefreshElements()
        end
        local element = state.elements and state.elements[state.index]
        local button = element and element.frame
        if button then
            local frameName = button:GetName() or ""
            if frameName == "LootCloseButton" then
                CloseLoot()
            else
                ActivateLootButton(button)
            end
        end
        state.pendingLootIndex = state.index
        state.nextScan = 0
        return
    end

    RefreshElements()
    if not state.active then return end
    local element = state.elements[state.index]
    if not element or not UsableButton(element.frame) then return end

    local ok
    if element.action then
        ok = pcall(element.action)
    else
        ok = pcall(function() element.frame:Click(element.mouseButton) end)
    end
    if not ok then UIPrint("Dieses UI-Element konnte nicht ausgeloest werden.") end
    state.nextScan = 0
end

function DinoController_UICancel()
    -- B is always JUMP, never Confirm/Loot. Do nothing special.
    if StaticPopup_EscapePressed and StaticPopup_EscapePressed() then return end
    if CloseMenus and CloseMenus() then return end
    if CloseAllWindows then CloseAllWindows() end
    state.nextScan = 0
end

local navigationFrame = CreateFrame("Frame", "DinoControllerUINavigationFrame")
navigationFrame:RegisterEvent("MERCHANT_SHOW")
navigationFrame:RegisterEvent("MERCHANT_CLOSED")
navigationFrame:RegisterEvent("MERCHANT_UPDATE")
navigationFrame:RegisterEvent("BAG_OPEN")
navigationFrame:RegisterEvent("BAG_CLOSED")
navigationFrame:RegisterEvent("BAG_UPDATE")
navigationFrame:RegisterEvent("LOOT_OPENED")
navigationFrame:RegisterEvent("LOOT_SLOT_CLEARED")
navigationFrame:RegisterEvent("LOOT_CLOSED")
navigationFrame:RegisterEvent("GOSSIP_SHOW")
navigationFrame:RegisterEvent("GOSSIP_CLOSED")
navigationFrame:RegisterEvent("QUEST_GREETING")
navigationFrame:RegisterEvent("QUEST_DETAIL")
navigationFrame:RegisterEvent("QUEST_PROGRESS")
navigationFrame:RegisterEvent("QUEST_COMPLETE")
navigationFrame:RegisterEvent("QUEST_FINISHED")
navigationFrame:RegisterEvent("TRAINER_SHOW")
navigationFrame:RegisterEvent("TRAINER_UPDATE")
navigationFrame:RegisterEvent("TRAINER_CLOSED")
navigationFrame:RegisterEvent("BANKFRAME_OPENED")
navigationFrame:RegisterEvent("BANKFRAME_CLOSED")
navigationFrame:RegisterEvent("MAIL_SHOW")
navigationFrame:RegisterEvent("MAIL_INBOX_UPDATE")
navigationFrame:RegisterEvent("MAIL_CLOSED")
navigationFrame:RegisterEvent("QUEST_LOG_UPDATE")
navigationFrame:SetScript("OnEvent", function()
    if event == "MERCHANT_SHOW" then
        OpenAllBags(1)
    elseif event == "MERCHANT_CLOSED" then
        CloseAllBags()
    elseif event == "LOOT_CLOSED" then
        LeaveUIMode()
        return
    end
    this.nextScan = 0
end)
navigationFrame:SetScript("OnUpdate", function()
    this.nextScan = (this.nextScan or 0) - arg1
    if this.nextScan <= 0 then
        this.nextScan = UI_SCAN_INTERVAL
        RefreshElements()
    end
end)
