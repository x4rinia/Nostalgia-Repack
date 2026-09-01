-- DinoController Phase 2.5 - aufloesungsunabhaengige Controller-Navigation
-- Author: x4rinia
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
    temporaryBindings = nil,
    suspendedFocus = nil
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

local function IsScrollable(scrollTarget)
    if not scrollTarget then return false end
    if type(scrollTarget) == "string" then
        scrollTarget = getglobal(scrollTarget)
    end
    if not scrollTarget then return false end

    -- Check if target is a ScrollBar
    if scrollTarget.GetMinMaxValues and scrollTarget.GetValue then
        local minVal, maxVal = scrollTarget:GetMinMaxValues()
        if minVal and maxVal and maxVal > minVal then
            return true
        end
        if scrollTarget.IsVisible and scrollTarget:IsVisible() then
            return true
        end
    end

    -- Check if target is a ScrollFrame with a child ScrollBar
    local name = scrollTarget.GetName and scrollTarget:GetName()
    if name then
        local scrollBar = getglobal(name .. "ScrollBar")
        if scrollBar then
            if scrollBar.GetMinMaxValues then
                local minVal, maxVal = scrollBar:GetMinMaxValues()
                if minVal and maxVal and maxVal > minVal then
                    return true
                end
            end
            if scrollBar.IsVisible and scrollBar:IsVisible() then
                return true
            end
        end
    end

    -- Check if target is a ScrollFrame
    if scrollTarget.GetVerticalScrollRange then
        local range = scrollTarget:GetVerticalScrollRange()
        if range and range > 0 then
            return true
        end
        if scrollTarget.IsVisible and scrollTarget:IsVisible() then
            return true
        end
    end

    return false
end

local function PerformScroll(element, direction)
    if not element or not element.isScrollArea then return false end
    if element.scrollAction then
        local ok, res = pcall(element.scrollAction, direction)
        if not ok then
            UIPrint("Scroll-Fehler: " .. tostring(res))
            return false
        end
        return res ~= false
    end

    local target = element.scrollTarget or element.frame
    if type(target) == "string" then target = getglobal(target) end
    if not target then return false end

    local name = target.GetName and target:GetName()
    local scrollBar = nil
    if target.GetMinMaxValues and target.GetValue then
        scrollBar = target
    elseif name then
        scrollBar = getglobal(name .. "ScrollBar")
    end

    local delta = (direction == "UP") and -1 or 1

    -- Check boundaries for ScrollBar
    if scrollBar and scrollBar.GetMinMaxValues and scrollBar.GetValue then
        local minVal, maxVal = scrollBar:GetMinMaxValues()
        local curVal = scrollBar:GetValue() or 0
        if delta < 0 and curVal <= (minVal + 0.01) then
            return false
        end
        if delta > 0 and curVal >= (maxVal - 0.01) then
            return false
        end

        -- 1. Try native ScrollUpButton / ScrollDownButton
        if scrollBar.GetName then
            local sbName = scrollBar:GetName()
            local upBtn = getglobal(sbName .. "ScrollUpButton")
            local downBtn = getglobal(sbName .. "ScrollDownButton")

            if delta < 0 and upBtn and upBtn.IsEnabled and upBtn:IsEnabled() == 1 then
                if upBtn.Click then
                    upBtn:Click()
                    return true
                end
            elseif delta > 0 and downBtn and downBtn.IsEnabled and downBtn:IsEnabled() == 1 then
                if downBtn.Click then
                    downBtn:Click()
                    return true
                end
            end
        end

        -- 2. Use ScrollBar SetValue
        if scrollBar.SetValue then
            local step = scrollBar.GetValueStep and scrollBar:GetValueStep()
            if not step or step < 5 then
                local pHeight = scrollBar.GetHeight and scrollBar:GetHeight()
                step = (pHeight and pHeight > 40) and math.floor(pHeight / 5) or 24
            end
            local newVal = curVal + (delta * step)
            if newVal < minVal then newVal = minVal end
            if newVal > maxVal then newVal = maxVal end
            scrollBar:SetValue(newVal)
            return true
        end
    end

    -- 3. Use ScrollFrame SetVerticalScroll
    local scrollFrame = target
    if scrollFrame and scrollFrame.GetVerticalScroll and scrollFrame.SetVerticalScroll then
        local cur = scrollFrame:GetVerticalScroll() or 0
        local range = (scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()) or 0
        if delta < 0 and cur <= 0.01 then
            return false
        end
        if delta > 0 and cur >= (range - 0.01) then
            return false
        end

        local fHeight = (scrollFrame.GetHeight and scrollFrame:GetHeight()) or 120
        local step = math.floor(fHeight / 5)
        if step < 20 then step = 24 end
        local newVal = cur + (delta * step)
        if newVal < 0 then newVal = 0 end
        if newVal > range then newVal = range end
        scrollFrame:SetVerticalScroll(newVal)
        return true
    end

    return false
end

local function UsableButton(button)
    if not button or not button.IsVisible or not button:IsVisible() then return nil end
    if not button.GetCenter then return nil end
    local x, y = button:GetCenter()
    if not x or not y then return nil end
    if button.IsEnabled then
        local enabled = button:IsEnabled()
        if enabled == nil or enabled == 0 then return nil end
    end
    return 1
end

local function FocusableButton(button)
    if not button or not button.IsVisible or not button:IsVisible() then return nil end
    if not button.GetCenter then return nil end
    local x, y = button:GetCenter()
    if not x or not y then return nil end
    return 1
end

local function UsableElement(element)
    if not element then return nil end
    if element.taxiNode then
        if not TaxiNodeGetType or TaxiNodeGetType(element.taxiNode) ~= "REACHABLE" then
            return nil
        end
    end
    if element.allowDisabled then
        return FocusableButton(element.frame)
    end
    return UsableButton(element.frame)
end

local function AddFrameButton(elements, key, button, mouseButton, action, allowDisabled)
    if allowDisabled then
        if not FocusableButton(button) then return end
    elseif not UsableButton(button) then
        return
    end
    table.insert(elements, {
        key = key,
        frame = button,
        mouseButton = mouseButton or "LeftButton",
        action = action,
        allowDisabled = allowDisabled
    })
end

local function AddButton(elements, name, mouseButton, action)
    AddFrameButton(elements, name, getglobal(name), mouseButton, action)
end

local function AddScrollArea(elements, key, scrollFrameOrBar, highlightFrame, scrollTarget, scrollAction)
    if not scrollFrameOrBar then return end
    if type(scrollFrameOrBar) == "string" then
        scrollFrameOrBar = getglobal(scrollFrameOrBar)
    end
    if not scrollFrameOrBar or not scrollFrameOrBar.IsVisible or not scrollFrameOrBar:IsVisible() then
        return
    end

    if type(highlightFrame) == "string" then
        highlightFrame = getglobal(highlightFrame)
    end
    if type(scrollTarget) == "string" then
        scrollTarget = getglobal(scrollTarget)
    end

    local target = scrollTarget or scrollFrameOrBar
    local hFrame = highlightFrame or scrollFrameOrBar

    if not IsScrollable(target) then
        return
    end

    if not hFrame.GetCenter then return end
    local cx, cy = hFrame:GetCenter()
    if not cx or not cy then return end

    table.insert(elements, {
        key = key or (scrollFrameOrBar.GetName and scrollFrameOrBar:GetName()) or "ScrollArea",
        frame = hFrame,
        scrollTarget = target,
        isScrollArea = true,
        scrollAction = scrollAction,
        mouseButton = "LeftButton"
    })
end

local function IsAlreadyRegistered(elements, frame, scrollTarget)
    local i
    for i = 1, table.getn(elements) do
        local elem = elements[i]
        if elem.frame == frame or (scrollTarget and elem.scrollTarget == scrollTarget) then
            return true
        end
    end
    return false
end

local function ScanScrollFrames(elements, parent, depth)
    if not parent or not parent.GetChildren or depth <= 0 then return end
    if not parent.IsVisible or not parent:IsVisible() then return end

    local children = { parent:GetChildren() }
    local index
    for index = 1, table.getn(children) do
        local child = children[index]
        if child and child.IsVisible and child:IsVisible() then
            local objType = child.GetObjectType and child:GetObjectType()
            local name = (child.GetName and child:GetName()) or ""

            if objType == "ScrollFrame" or objType == "Slider" or string.find(name, "Scroll") then
                local isChildButton = string.find(name, "ScrollUpButton$") or string.find(name, "ScrollDownButton$") or string.find(name, "Thumb$")
                if not isChildButton then
                    local scrollTarget = child
                    local highlightFrame = child

                    if objType == "Slider" and child:GetParent() then
                        local parentObj = child:GetParent()
                        if parentObj and parentObj.GetObjectType and parentObj:GetObjectType() == "ScrollFrame" then
                            scrollTarget = parentObj
                            highlightFrame = parentObj
                        end
                    end

                    if IsScrollable(scrollTarget) and not IsAlreadyRegistered(elements, highlightFrame, scrollTarget) then
                        local key = (highlightFrame.GetName and highlightFrame:GetName()) or (name ~= "" and name) or ("DiscoveredScroll_" .. (table.getn(elements) + 1))
                        AddScrollArea(elements, key, highlightFrame, highlightFrame, scrollTarget)
                    end
                end
            end

            ScanScrollFrames(elements, child, depth - 1)
        end
    end
end

local function AddRange(elements, prefix, first, last, suffix, mouseButton)
    local index
    for index = first, last do
        AddButton(elements, prefix .. index .. (suffix or ""), mouseButton)
    end
end

local function AddContainers(elements, mouseButton, customAction)
    local frameIndex, itemIndex
    local count = NUM_CONTAINER_FRAMES or 12
    for frameIndex = 1, count do
        if Visible("ContainerFrame" .. frameIndex) then
            for itemIndex = 1, 20 do
                local name = "ContainerFrame" .. frameIndex .. "Item" .. itemIndex
                local btn = getglobal(name)
                if UsableButton(btn) then
                    local containerBtn = btn
                    local action = nil
                    if customAction then
                        action = function() return customAction(containerBtn) end
                    end
                    AddFrameButton(elements, name, containerBtn, mouseButton or "RightButton", action)
                end
            end
            AddButton(elements, "ContainerFrame" .. frameIndex .. "CloseButton")
        end
    end
end

local function ResolveMerchantSlot(button)
    if not button then return nil end
    local slot = button.slot
    if not slot or slot <= 0 then
        slot = button:GetID()
    end
    if not slot or slot <= 0 then
        local name = (button.GetName and button:GetName()) or ""
        local itemIndex = string.match(name, "^MerchantItem(%d+)ItemButton$")
        if itemIndex then
            local page = (MerchantFrame and MerchantFrame.page) or 1
            local perPage = MERCHANT_ITEMS_PER_PAGE or 10
            slot = ((page - 1) * perPage) + tonumber(itemIndex)
        end
    end
    return slot
end

local function ActivateMerchantButton(button)
    if not button or not button:IsVisible() then return nil end
    local slot = ResolveMerchantSlot(button)
    if not slot or slot < 1 then return nil end

    if CursorHasItem and CursorHasItem() and ClearCursor then
        ClearCursor()
    end

    local selectedTab = (MerchantFrame and MerchantFrame.selectedTab) or 1

    if selectedTab == 1 then
        local maxItems = GetMerchantNumItems and GetMerchantNumItems()
        if maxItems and slot > maxItems then
            return nil
        end
        local name, texture, price, quantity, numAvailable, isUsable = GetMerchantItemInfo(slot)
        if not name then
            return nil
        end

        local ok, err = pcall(BuyMerchantItem, slot, 1)
        if not ok then
            UIPrint("Kauf fehlgeschlagen: " .. tostring(err))
            return nil
        end
        return 1
    else
        local ok, err = pcall(BuybackItem, slot)
        if not ok then
            UIPrint("Rueckkauf fehlgeschlagen: " .. tostring(err))
            return nil
        end
        return 1
    end
end

local function ActivateMerchantBuyBackItem(button)
    if not button or not button:IsVisible() then return nil end
    if CursorHasItem and CursorHasItem() and ClearCursor then
        ClearCursor()
    end
    local numBuyback = (GetNumBuybackItems and GetNumBuybackItems()) or 0
    if numBuyback < 1 then
        return nil
    end
    local ok, err = pcall(BuybackItem, numBuyback)
    if not ok then
        UIPrint("Rueckkauf fehlgeschlagen: " .. tostring(err))
        return nil
    end
    return 1
end

local function ActivateContainerItemInMerchant(button)
    if not button or not button:IsVisible() then return nil end
    local parent = button:GetParent()
    local bagID = parent and parent.GetID and parent:GetID()
    local slotID = button.GetID and button:GetID()
    if bagID and slotID then
        local texture, itemCount, locked = GetContainerItemInfo(bagID, slotID)
        if not texture then return nil end
        local ok, err = pcall(UseContainerItem, bagID, slotID)
        if not ok then
            UIPrint("Verkauf fehlgeschlagen: " .. tostring(err))
            return nil
        end
        return 1
    end
    return nil
end

local function AddMerchant(elements)
    local index
    for index = 1, 12 do
        local name = "MerchantItem" .. index .. "ItemButton"
        local button = getglobal(name)
        if UsableButton(button) then
            local merchantBtn = button
            AddButton(elements, name, "RightButton", function()
                return ActivateMerchantButton(merchantBtn)
            end)
        end
    end

    local buybackBtn = getglobal("MerchantBuyBackItemItemButton")
    if UsableButton(buybackBtn) then
        AddButton(elements, "MerchantBuyBackItemItemButton", "RightButton", function()
            return ActivateMerchantBuyBackItem(buybackBtn)
        end)
    end

    AddButton(elements, "MerchantPrevPageButton")
    AddButton(elements, "MerchantNextPageButton")
    AddButton(elements, "MerchantRepairItemButton")
    AddButton(elements, "MerchantRepairAllButton")
    AddButton(elements, "MerchantFrameTab1")
    AddButton(elements, "MerchantFrameTab2")
    AddButton(elements, "MerchantFrameCloseButton")
    AddContainers(elements, "RightButton", ActivateContainerItemInMerchant)
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

-- Vanilla 1.12.1 defines four GroupLootFrame slots. Each slot inherits the
-- original GroupLootFrameTemplate and owns these exact buttons:
--   RollButton  -> RollOnLoot(rollID, 1) (Need)
--   GreedButton -> RollOnLoot(rollID, 2) (Greed)
--   PassButton  -> RollOnLoot(rollID, 0) (Pass)
-- Keep the real Blizzard frames as navigation targets, but invoke the native
-- roll API directly so controller activation never depends on a mouse click.
local GROUP_LOOT_ACTIONS = {
    { suffix = "RollButton", choice = "need", rollType = 1 },
    { suffix = "GreedButton", choice = "greed", rollType = 2 },
    { suffix = "PassButton", choice = "pass", rollType = 0 }
}

local function HasVisibleGroupLootRoll()
    local frameIndex
    for frameIndex = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local frame = getglobal("GroupLootFrame" .. frameIndex)
        if frame and frame.IsVisible and frame:IsVisible() then
            return 1
        end
    end
    return nil
end

local function ActivateGroupLootRoll(rollFrame, rollType)
    if not rollFrame or not rollFrame.IsVisible or not rollFrame:IsVisible() then
        return nil
    end
    local rollID = rollFrame.rollID
    if rollID == nil or not RollOnLoot then return nil end

    local ok, err = pcall(function()
        RollOnLoot(rollID, rollType)
    end)
    if not ok then
        UIPrint("Loot-Roll konnte nicht ausgefuehrt werden: " .. tostring(err))
        return nil
    end
    return 1
end

local function AddGroupLootRollAction(elements, rollFrame, frameIndex, actionInfo)
    local buttonName = "GroupLootFrame" .. frameIndex .. actionInfo.suffix
    local button = getglobal(buttonName)
    if not UsableButton(button) then return end

    AddFrameButton(elements, buttonName, button, "LeftButton", function()
        return ActivateGroupLootRoll(rollFrame, actionInfo.rollType)
    end)
    local element = elements[table.getn(elements)]
    element.lootRollFrameIndex = frameIndex
    element.lootRollID = rollFrame.rollID
    element.lootRollChoice = actionInfo.choice
end

local function AddGroupLootRolls(elements)
    local originalCount = table.getn(elements)
    local frameIndex, actionIndex
    for frameIndex = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
        local rollFrame = getglobal("GroupLootFrame" .. frameIndex)
        if rollFrame and rollFrame.IsVisible and rollFrame:IsVisible() then
            for actionIndex = 1, table.getn(GROUP_LOOT_ACTIONS) do
                AddGroupLootRollAction(elements, rollFrame, frameIndex, GROUP_LOOT_ACTIONS[actionIndex])
            end
        end
    end
    return table.getn(elements) > originalCount
end

local function AddGossip(elements)
    AddRange(elements, "GossipTitleButton", 1, 16)
    AddScrollArea(elements, "GossipGreetingScrollArea", "GossipGreetingScrollFrame", "GossipGreetingScrollFrame", "GossipGreetingScrollFrame")
    AddButton(elements, "GossipFrameGreetingGoodbyeButton")
    AddButton(elements, "GossipFrameCloseButton")
end

local function AddQuest(elements)
    if Visible("QuestFrameRewardPanel") then
        local choices = GetNumQuestChoices() or 0
        AddRange(elements, "QuestRewardItem", 1, choices)
        AddScrollArea(elements, "QuestRewardScrollArea", "QuestRewardScrollFrame", "QuestRewardScrollFrame", "QuestRewardScrollFrame")
        AddButton(elements, "QuestFrameCompleteQuestButton")
        AddButton(elements, "QuestFrameCancelButton")
    elseif Visible("QuestFrameProgressPanel") then
        AddScrollArea(elements, "QuestProgressScrollArea", "QuestProgressScrollFrame", "QuestProgressScrollFrame", "QuestProgressScrollFrame")
        AddButton(elements, "QuestFrameCompleteButton")
        AddButton(elements, "QuestFrameGoodbyeButton")
    elseif Visible("QuestFrameDetailPanel") then
        AddScrollArea(elements, "QuestDetailScrollArea", "QuestDetailScrollFrame", "QuestDetailScrollFrame", "QuestDetailScrollFrame")
        AddButton(elements, "QuestFrameAcceptButton")
        AddButton(elements, "QuestFrameDeclineButton")
    elseif Visible("QuestFrameGreetingPanel") then
        AddRange(elements, "QuestTitleButton", 1, 32)
        AddScrollArea(elements, "QuestGreetingScrollArea", "QuestGreetingScrollFrame", "QuestGreetingScrollFrame", "QuestGreetingScrollFrame")
        AddButton(elements, "QuestFrameGreetingGoodbyeButton")
    end
    AddButton(elements, "QuestFrameCloseButton")
end

local function AddTrainer(elements)
    AddRange(elements, "ClassTrainerSkill", 1, 11)
    AddScrollArea(elements, "ClassTrainerListScrollArea", "ClassTrainerListScrollFrameScrollBar", "ClassTrainerListScrollFrameScrollBar", "ClassTrainerListScrollFrame")
    AddScrollArea(elements, "ClassTrainerDetailScrollArea", "ClassTrainerDetailScrollFrame", "ClassTrainerDetailScrollFrame", "ClassTrainerDetailScrollFrame")
    AddButton(elements, "ClassTrainerAvailableButton")
    AddButton(elements, "ClassTrainerUnavailableButton")
    AddButton(elements, "ClassTrainerUsedButton")
    AddButton(elements, "ClassTrainerTrainButton")
    AddButton(elements, "ClassTrainerCancelButton")
    AddButton(elements, "ClassTrainerFrameCloseButton")
end

local function FindClickableChild(frame, depth)
    if not frame or not frame.GetChildren or depth <= 0 then return nil end
    local children = { frame:GetChildren() }
    local index
    for index = 1, table.getn(children) do
        local child = children[index]
        if child and child.Click and UsableButton(child) then
            return child
        end
    end
    for index = 1, table.getn(children) do
        local child = FindClickableChild(children[index], depth - 1)
        if child then return child end
    end
    return nil
end

local function AddBankPurchaseButton(elements)
    local button = getglobal("BankFramePurchaseButton") or
        getglobal("BankFramePurchaseInfoPurchaseButton")
    if not UsableButton(button) then
        button = FindClickableChild(getglobal("BankFramePurchaseInfo"), 3)
    end
    AddFrameButton(elements, "BankPurchaseButton", button)
end

local function AddBank(elements)
    AddBankPurchaseButton(elements)
    AddRange(elements, "BankFrameItem", 1, 24, nil, "RightButton")
    AddRange(elements, "BankFrameBag", 1, 6)
    AddButton(elements, "BankCloseButton")
    AddContainers(elements, "RightButton")
end

local function AddAuction(elements)
    if Visible("AuctionFrameBrowse") then
        AddButton(elements, "BrowseSearchButton")
        AddRange(elements, "BrowseButton", 1, 8)
        AddScrollArea(elements, "BrowseScrollArea", "BrowseScrollFrameScrollBar", "BrowseScrollFrameScrollBar", "BrowseScrollFrame")
        AddButton(elements, "BrowseBuyoutButton")
        AddButton(elements, "BrowseBidButton")
        AddButton(elements, "BrowsePrevPageButton")
        AddButton(elements, "BrowseNextPageButton")
        AddScrollArea(elements, "BrowseFilterScrollArea", "BrowseFilterScrollFrameScrollBar", "BrowseFilterScrollFrameScrollBar", "BrowseFilterScrollFrame")
        AddRange(elements, "AuctionFilterButton", 1, 15)
        AddButton(elements, "IsUsableCheckButton")
        AddButton(elements, "BrowseCloseButton")
    elseif Visible("AuctionFrameBid") then
        AddRange(elements, "BidButton", 1, 9)
        AddScrollArea(elements, "BidScrollArea", "BidScrollFrameScrollBar", "BidScrollFrameScrollBar", "BidScrollFrame")
        AddButton(elements, "BidBuyoutButton")
        AddButton(elements, "BidBidButton")
        AddButton(elements, "BidPrevPageButton")
        AddButton(elements, "BidNextPageButton")
        AddButton(elements, "BidCloseButton")
    elseif Visible("AuctionFrameAuctions") then
        AddButton(elements, "AuctionsItemButton", "RightButton")
        AddButton(elements, "AuctionsCreateAuctionButton")
        AddRange(elements, "AuctionsButton", 1, 9)
        AddScrollArea(elements, "AuctionsScrollArea", "AuctionsScrollFrameScrollBar", "AuctionsScrollFrameScrollBar", "AuctionsScrollFrame")
        AddButton(elements, "AuctionsCancelAuctionButton")
        AddButton(elements, "AuctionsPrevPageButton")
        AddButton(elements, "AuctionsNextPageButton")
        AddButton(elements, "AuctionsShortAuctionButton")
        AddButton(elements, "AuctionsMediumAuctionButton")
        AddButton(elements, "AuctionsLongAuctionButton")
        AddButton(elements, "AuctionsCloseButton")
    end

    AddRange(elements, "AuctionFrameTab", 1, 3)
    AddButton(elements, "AuctionFrameCloseButton")
end

local function AddMail(elements)
    if Visible("OpenMailFrame") then
        AddButton(elements, "OpenMailLetterButton")
        AddButton(elements, "OpenMailPackageButton")
        AddButton(elements, "OpenMailMoneyButton")
        AddScrollArea(elements, "OpenMailScrollArea", "OpenMailScrollFrame", "OpenMailScrollFrame", "OpenMailScrollFrame")
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
        AddScrollArea(elements, "SendMailScrollArea", "SendMailScrollFrame", "SendMailScrollFrame", "SendMailScrollFrame")
        AddButton(elements, "SendMailMailButton")
        AddButton(elements, "SendMailCancelButton")
        AddButton(elements, "MailFrameTab1")
        AddButton(elements, "MailFrameTab2")
        AddButton(elements, "InboxCloseButton")
    end
end

local function AddTaxi(elements)
    local numNodes = (NumTaxiNodes and NumTaxiNodes()) or 0
    local maxButtons = TAXI_BUTTONS or 64
    if numNodes > maxButtons then numNodes = maxButtons end

    local index
    for index = 1, numNodes do
        local button = getglobal("TaxiButton" .. index)
        local nodeIndex = button and button.GetID and button:GetID()
        -- Vanilla zeigt CURRENT, REACHABLE und DISTANT mit denselben nativen
        -- Buttons an; nur REACHABLE ist ein tatsaechliches Flugziel.
        if nodeIndex and UsableButton(button) and TaxiNodeGetType and
           TaxiNodeGetType(nodeIndex) == "REACHABLE" then
            table.insert(elements, {
                key = "TaxiButton" .. index,
                frame = button,
                mouseButton = "LeftButton",
                taxiNode = nodeIndex
            })
        end
    end
end

local function PlayerIsHunter()
    local _, classToken = UnitClass("player")
    return classToken == "HUNTER"
end

local function ActivateStableSlot(button)
    if not button or not button.IsVisible or not button:IsVisible() then return nil end
    if button.IsEnabled and button:IsEnabled() ~= 1 then return nil end
    if not button.Click then return nil end
    button:Click("LeftButton")
    return 1
end

local function AddStableSlot(elements, name)
    local button = getglobal(name)
    if not button then return end
    local stableButton = button
    AddFrameButton(elements, name, stableButton, "LeftButton", function()
        return ActivateStableSlot(stableButton)
    end, 1)
end

local function AddStable(elements)
    AddStableSlot(elements, "PetStableCurrentPet")

    local index
    for index = 1, (NUM_PET_STABLE_SLOTS or 2) do
        AddStableSlot(elements, "PetStableStabledPet" .. index)
    end

    AddButton(elements, "PetStablePurchaseButton")
    AddButton(elements, "PetStableModelRotateLeftButton")
    AddButton(elements, "PetStableModelRotateRightButton")
    AddButton(elements, "PetStableFrameCloseButton")
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
    AddContainers(elements, "RightButton")
    local index
    for index = 1, table.getn(characterSlots) do
        AddButton(elements, characterSlots[index])
    end
    if Visible("ReputationFrame") then
        AddRange(elements, "ReputationHeader", 1, 15)
        AddScrollArea(elements, "ReputationScrollArea", "ReputationListScrollFrameScrollBar", "ReputationListScrollFrameScrollBar", "ReputationListScrollFrame")
    elseif Visible("SkillFrame") then
        AddRange(elements, "SkillRankFrame", 1, 12)
        AddScrollArea(elements, "SkillListScrollArea", "SkillListScrollFrameScrollBar", "SkillListScrollFrameScrollBar", "SkillListScrollFrame")
        AddScrollArea(elements, "SkillDetailScrollArea", "SkillDetailScrollFrame", "SkillDetailScrollFrame", "SkillDetailScrollFrame")
    end
    AddRange(elements, "CharacterFrameTab", 1, 4)
    AddButton(elements, "CharacterFrameCloseButton")
end

local function FrameIntersectsViewport(frame, viewport)
    if not frame or not viewport then return nil end
    if not frame.GetLeft or not viewport.GetLeft then return nil end

    local left, right = frame:GetLeft(), frame:GetRight()
    local bottom, top = frame:GetBottom(), frame:GetTop()
    local viewLeft, viewRight = viewport:GetLeft(), viewport:GetRight()
    local viewBottom, viewTop = viewport:GetBottom(), viewport:GetTop()
    if not left or not right or not bottom or not top or
       not viewLeft or not viewRight or not viewBottom or not viewTop then
        return nil
    end

    return right > viewLeft and left < viewRight and top > viewBottom and bottom < viewTop
end

local function ActivateTalentButton(button)
    if not button then return false end
    if button.IsEnabled and button:IsEnabled() == 0 then return false end
    button:Click("LeftButton")
    return true
end

local function ActivateTalentTab(button)
    if not button then return false end
    button:Click("LeftButton")
    state.pendingTalentFocus = 1
    return true
end

local function AddTalent(elements)
    local viewport = getglobal("TalentFrameScrollFrame")
    local maxTalents = MAX_NUM_TALENTS or 20
    local index
    for index = 1, maxTalents do
        local name = "TalentFrameTalent" .. index
        local button = getglobal(name)
        if button and FrameIntersectsViewport(button, viewport) then
            local talentButton = button
            AddFrameButton(elements, name, talentButton, "LeftButton", function()
                return ActivateTalentButton(talentButton)
            end, 1)
        end
    end

    AddScrollArea(elements, "TalentFrameScrollArea", "TalentFrameScrollFrame",
        "TalentFrameScrollFrame", "TalentFrameScrollFrame")

    local numTabs = GetNumTalentTabs and GetNumTalentTabs() or 0
    for index = 1, numTabs do
        local name = "TalentFrameTab" .. index
        local tabButton = getglobal(name)
        if tabButton and tabButton.IsVisible and tabButton:IsVisible() then
            local talentTab = tabButton
            AddFrameButton(elements, name, talentTab, "LeftButton", function()
                return ActivateTalentTab(talentTab)
            end)
        end
    end

    AddButton(elements, "TalentFrameCancelButton")
    AddButton(elements, "TalentFrameCloseButton")
end

local function ShowQuestWatchError(message)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
    else
        UIPrint(message)
    end
end

local function RemoveQuestFromWatchList(questIndex)
    if not QUEST_WATCH_LIST then return end

    local index
    for index = table.getn(QUEST_WATCH_LIST), 1, -1 do
        local watch = QUEST_WATCH_LIST[index]
        if watch and watch.index == questIndex then
            tremove(QUEST_WATCH_LIST, index)
        end
    end
end

local function ToggleSelectedQuestWatch()
    local questIndex = GetQuestLogSelection and GetQuestLogSelection()
    if not questIndex or questIndex < 1 then
        UIPrint("Bitte zuerst eine Quest auswaehlen.")
        return
    end

    local title, level, questTag, isHeader = GetQuestLogTitle(questIndex)
    if not title or isHeader then
        UIPrint("Bitte zuerst eine Quest auswaehlen.")
        return
    end

    if IsQuestWatched(questIndex) then
        RemoveQuestFromWatchList(questIndex)
        RemoveQuestWatch(questIndex)
    else
        if GetNumQuestLeaderBoards(questIndex) == 0 then
            ShowQuestWatchError(QUEST_WATCH_NO_OBJECTIVES)
            return
        end
        if GetNumQuestWatches() >= MAX_WATCHABLE_QUESTS then
            ShowQuestWatchError(format(QUEST_WATCH_TOO_MANY, MAX_WATCHABLE_QUESTS))
            return
        end

        if AutoQuestWatch_Insert and QUEST_WATCH_NO_EXPIRE then
            AutoQuestWatch_Insert(questIndex, QUEST_WATCH_NO_EXPIRE)
        else
            AddQuestWatch(questIndex)
        end
    end

    if QuestWatch_Update then QuestWatch_Update() end
    if QuestLog_Update then QuestLog_Update() end
end

local function AddQuestLog(elements)
    AddRange(elements, "QuestLogTitle", 1, 6)
    AddScrollArea(elements, "QuestLogListScrollArea", "QuestLogListScrollFrameScrollBar", "QuestLogListScrollFrameScrollBar", "QuestLogListScrollFrame")
    AddScrollArea(elements, "QuestLogDetailScrollArea", "QuestLogDetailScrollFrame", "QuestLogDetailScrollFrame", "QuestLogDetailScrollFrame")
    if QuestLogFrame then
        ScanScrollFrames(elements, QuestLogFrame, 5)
    end
    AddRange(elements, "QuestLogItem", 1, 10)
    AddButton(elements, "QuestLogCollapseAllButton")
    AddButton(elements, "QuestLogTrack", "LeftButton", ToggleSelectedQuestWatch)
    AddButton(elements, "QuestFramePushQuestButton")
    AddButton(elements, "QuestLogFrameAbandonButton")
    AddButton(elements, "QuestFrameExitButton")
    AddButton(elements, "QuestLogFrameCloseButton")
end

local function AddWorldMap(elements)
    AddButton(elements, "WorldMapZoomOutButton")
    AddButton(elements, "WorldMapContinentDropDownButton")
    AddButton(elements, "WorldMapZoneDropDownButton")
    AddButton(elements, "WorldMapFrameCloseButton")
end

local function ActivateWorldStateScoreLeave()
    if not Visible("WorldStateScoreFrame") or
       not UsableButton(getglobal("WorldStateScoreFrameLeaveButton")) or
       not LeaveBattlefield then
        return nil
    end
    -- This is the exact native function used by the Vanilla 1.12.1
    -- WorldStateScoreFrameLeaveButton OnClick script.
    LeaveBattlefield()
    return 1
end

local function ActivateWorldStateScoreTab(tab)
    if not tab or not UsableButton(tab) or not WorldStateScoreFrameTab_OnClick then
        return nil
    end
    WorldStateScoreFrameTab_OnClick(tab)
    return 1
end

local function CloseWorldStateScoreFrame()
    if not Visible("WorldStateScoreFrame") or not HideUIPanel then return nil end
    -- UIPanelCloseButton uses this native Blizzard panel function as well.
    HideUIPanel(WorldStateScoreFrame)
    return 1
end

local function AddWorldStateScore(elements)
    local leaveButton = getglobal("WorldStateScoreFrameLeaveButton")
    if UsableButton(leaveButton) then
        AddFrameButton(elements, "WorldStateScoreFrameLeaveButton", leaveButton, "LeftButton",
            ActivateWorldStateScoreLeave)
    end

    local tabIndex
    for tabIndex = 1, 3 do
        local tabName = "WorldStateScoreFrameTab" .. tabIndex
        local tab = getglobal(tabName)
        if UsableButton(tab) then
            local scoreTab = tab
            AddFrameButton(elements, tabName, scoreTab, "LeftButton", function()
                return ActivateWorldStateScoreTab(scoreTab)
            end)
        end
    end

    -- The 22 score rows and their headers have no OnClick action in the
    -- original FrameXML. Only expose the native FauxScrollFrame when needed.
    AddScrollArea(elements, "WorldStateScoreScrollArea", "WorldStateScoreScrollFrame",
        "WorldStateScoreScrollFrame", "WorldStateScoreScrollFrame")

    local closeButton = getglobal("WorldStateScoreFrameCloseButton")
    if UsableButton(closeButton) then
        AddFrameButton(elements, "WorldStateScoreFrameCloseButton", closeButton, "LeftButton",
            CloseWorldStateScoreFrame)
    end
end

local function FindFirstMatchingElement(elements, pattern)
    local index
    for index = 1, table.getn(elements) do
        local key = elements[index].key
        if key and string.find(key, pattern) then
            return index
        end
    end
    return nil
end

local function FindInitialMerchantBagSlot(elements)
    local firstBagSlot = nil
    local index
    for index = 1, table.getn(elements) do
        local element = elements[index]
        if element.key and string.find(element.key, "^ContainerFrame%d+Item%d+$") then
            if not firstBagSlot then firstBagSlot = index end

            local button = element.frame
            local parent = button and button:GetParent()
            if parent and parent.GetID and button.GetID then
                local texture = GetContainerItemInfo(parent:GetID(), button:GetID())
                if texture then return index end
            end
        end
    end
    return firstBagSlot
end

local function AddDropDownList(elements, listIndex)
    local prefix = "DropDownList" .. listIndex
    local listFrame = getglobal(prefix)
    if not listFrame or not listFrame.IsVisible or not listFrame:IsVisible() then return end

    local maxButtons = UIDROPDOWNMENU_MAXBUTTONS or 32
    local buttonIndex
    for buttonIndex = 1, maxButtons do
        local btnName = prefix .. "Button" .. buttonIndex
        local btn = getglobal(btnName)
        if btn and btn.IsVisible and btn:IsVisible() then
            AddButton(elements, btnName)
        end
    end

    ScanScrollFrames(elements, listFrame, 3)
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

    -- Loot rolls are transient and time-sensitive. They take navigation
    -- priority while visible; the previous context/focus is restored below
    -- as soon as the final roll frame disappears.
    if AddGroupLootRolls(elements) then
        return "lootroll", elements
    end

    if Visible("DropDownList1") then
        context = "dropdown"
        AddDropDownList(elements, 1)
        if Visible("DropDownList2") then
            AddDropDownList(elements, 2)
        end
        return context, elements
    end

    local popupIndex
    for popupIndex = 1, 4 do
        if Visible("StaticPopup" .. popupIndex) then
            context = "popup"
            AddStaticPopup(elements)
            return context, elements
        end
    end

    if Visible("WorldStateScoreFrame") then
        context = "battlegroundscore"
        AddWorldStateScore(elements)
    elseif Visible("TaxiFrame") then
        context = "taxi"
        AddTaxi(elements)
    elseif Visible("WorldMapFrame") then
        context = "worldmap"
        AddWorldMap(elements)
    elseif Visible("QuestFrame") then
        context = "quest"
        AddQuest(elements)
        ScanScrollFrames(elements, QuestFrame, 4)
    elseif Visible("GossipFrame") then
        context = "gossip"
        AddGossip(elements)
        ScanScrollFrames(elements, GossipFrame, 4)
    elseif Visible("MerchantFrame") then
        context = "merchant"
        AddMerchant(elements)
        ScanScrollFrames(elements, MerchantFrame, 4)
    elseif Visible("LootFrame") then
        context = "loot"
        AddLoot(elements)
    elseif Visible("ClassTrainerFrame") then
        context = "trainer"
        AddTrainer(elements)
        ScanScrollFrames(elements, ClassTrainerFrame, 4)
    elseif Visible("BankFrame") then
        context = "bank"
        AddBank(elements)
        ScanScrollFrames(elements, BankFrame, 4)
    elseif Visible("AuctionFrame") then
        context = "auction"
        AddAuction(elements)
        ScanScrollFrames(elements, AuctionFrame, 4)
    elseif Visible("OpenMailFrame") or Visible("MailFrame") then
        context = "mail"
        AddMail(elements)
        ScanScrollFrames(elements, OpenMailFrame or MailFrame, 4)
    elseif PlayerIsHunter() and Visible("PetStableFrame") then
        context = "stable"
        AddStable(elements)
        ScanScrollFrames(elements, PetStableFrame, 4)
    elseif Visible("QuestLogFrame") then
        context = "questlog"
        AddQuestLog(elements)
    elseif Visible("TalentFrame") then
        context = "talent"
        AddTalent(elements)
    elseif Visible("CharacterFrame") then
        context = "character"
        AddCharacter(elements)
        ScanScrollFrames(elements, CharacterFrame, 4)
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
    if not element or not element.frame or element.isScrollArea then return end
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
    if not element or not element.frame or element.isScrollArea then return end
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
    if not state.active or not element or not UsableElement(element) then
        if state.tooltipElement then
            TriggerOnLeave(state.tooltipElement)
            state.tooltipElement = nil
            state.tooltipFrame = nil
        end
        highlight:Hide()
        return
    end

    local currentFrame = element.frame
    if state.tooltipFrame ~= currentFrame then
        if state.tooltipElement then
            TriggerOnLeave(state.tooltipElement)
        end
        state.tooltipFrame = currentFrame
        state.tooltipElement = element
        TriggerOnEnter(element)
    end

    if Visible("DropDownList1") and DropDownList1 and DropDownList1:IsVisible() then
        if highlight:GetParent() ~= DropDownList1 then
            highlight:SetParent(DropDownList1)
            highlight:SetFrameStrata("TOOLTIP")
            highlight:SetFrameLevel(DropDownList1:GetFrameLevel() + 50)
        end
    elseif state.context == "worldmap" and WorldMapFrame and WorldMapFrame:IsVisible() then
        if highlight:GetParent() ~= WorldMapFrame then
            highlight:SetParent(WorldMapFrame)
            highlight:SetFrameStrata("TOOLTIP")
            highlight:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 50)
        end
    else
        if highlight:GetParent() ~= UIParent then
            highlight:SetParent(UIParent)
            highlight:SetFrameStrata("TOOLTIP")
        end
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

    if state.context == "worldmap" or (WorldMapFrame and WorldMapFrame:IsVisible()) then
        SaveAndBind("NUMPAD8", "")
        SaveAndBind("NUMPAD2", "")
        SaveAndBind("NUMPAD4", "")
        SaveAndBind("NUMPAD6", "")
        SaveAndBind("NUMPAD7", "")
        SaveAndBind("NUMPADMINUS", "")
        SaveAndBind("NUMPADPLUS", "")
        SaveAndBind("F12", "")
    end

    if DinoController_SetUIMode then DinoController_SetUIMode(1, state.context) end
end

local function LeaveUIMode()
    if not state.active then return end
    if state.tooltipElement then
        TriggerOnLeave(state.tooltipElement)
        state.tooltipElement = nil
        state.tooltipFrame = nil
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
    state.suspendedFocus = nil
    if highlight:GetParent() ~= UIParent then
        highlight:SetParent(UIParent)
        highlight:SetFrameStrata("TOOLTIP")
    end
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

    local resumeFocus = nil
    if context == "lootroll" and oldContext ~= "lootroll" then
        if state.active and oldContext then
            state.suspendedFocus = {
                context = oldContext,
                key = oldKey,
                index = oldIndex
            }
        else
            state.suspendedFocus = nil
        end
    elseif oldContext == "lootroll" and context ~= "lootroll" then
        resumeFocus = state.suspendedFocus
        state.suspendedFocus = nil
    end

    state.context = context
    state.elements = elements
    if not state.active then
        EnterUIMode()
    elseif context ~= oldContext and DinoController_SetUIMode then
        DinoController_SetUIMode(1, context)
    end

    local preferredIndex = nil
    if context == "lootroll" and oldContext ~= "lootroll" then
        preferredIndex = 1
    elseif context == "lootroll" and oldElement and oldElement.lootRollFrameIndex then
        local index
        for index = 1, table.getn(elements) do
            if elements[index].key == oldKey then
                preferredIndex = index
                break
            end
        end
        if not preferredIndex then
            local nextFrameIndex = nil
            local firstFrameIndex = nil
            for index = 1, table.getn(elements) do
                local frameIndex = elements[index].lootRollFrameIndex
                if frameIndex then
                    if not firstFrameIndex or frameIndex < firstFrameIndex then
                        firstFrameIndex = frameIndex
                    end
                    if frameIndex > oldElement.lootRollFrameIndex and
                       (not nextFrameIndex or frameIndex < nextFrameIndex) then
                        nextFrameIndex = frameIndex
                    end
                end
            end
            nextFrameIndex = nextFrameIndex or firstFrameIndex
            if nextFrameIndex then
                for index = 1, table.getn(elements) do
                    local element = elements[index]
                    if element.lootRollFrameIndex == nextFrameIndex and
                       element.lootRollChoice == oldElement.lootRollChoice then
                        preferredIndex = index
                        break
                    end
                end
                if not preferredIndex then
                    for index = 1, table.getn(elements) do
                        if elements[index].lootRollFrameIndex == nextFrameIndex then
                            preferredIndex = index
                            break
                        end
                    end
                end
            end
        end
    elseif resumeFocus and resumeFocus.context == context then
        if resumeFocus.key then
            local index
            for index = 1, table.getn(elements) do
                if elements[index].key == resumeFocus.key then
                    preferredIndex = index
                    break
                end
            end
        end
        if not preferredIndex and resumeFocus.index then
            preferredIndex = resumeFocus.index
            if preferredIndex > table.getn(elements) then
                preferredIndex = table.getn(elements)
            end
            if preferredIndex < 1 then preferredIndex = 1 end
        end
    elseif context == "merchant" and state.pendingMerchantBagFocus then
        preferredIndex = FindInitialMerchantBagSlot(elements)
        if preferredIndex then state.pendingMerchantBagFocus = nil end
    elseif context == "questlog" and (state.pendingQuestLogFocus or context ~= oldContext) then
        preferredIndex = FindFirstMatchingElement(elements, "^QuestFrameExitButton$") or 1
        state.pendingQuestLogFocus = nil
    elseif context == "bank" and (state.pendingBankFocus or context ~= oldContext) then
        preferredIndex = FindFirstMatchingElement(elements, "^BankPurchaseButton$")
        if preferredIndex then state.pendingBankFocus = nil end
    elseif context == "talent" and (state.pendingTalentFocus or context ~= oldContext) then
        preferredIndex = FindFirstMatchingElement(elements, "^TalentFrameTalent%d+$")
        if preferredIndex then state.pendingTalentFocus = nil end
    elseif context == "stable" and context ~= oldContext then
        preferredIndex = FindFirstMatchingElement(elements, "^PetStableCurrentPet$") or
            FindFirstMatchingElement(elements, "^PetStableStabledPet%d+$") or 1
    end

    if preferredIndex then
        state.index = preferredIndex
    elseif context ~= oldContext then
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

function DinoController_RequestQuestLogFocus()
    state.pendingQuestLogFocus = 1
    RefreshElements()
end

function DinoController_RequestWorldMapFocus()
    state.index = 1
    RefreshElements()
end

function DinoController_RequestTalentFocus()
    state.pendingTalentFocus = 1
    RefreshElements()
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
            if elem and elem.frame and UsableElement(elem) then
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

local function MoveGroupLootRoll(dir)
    local current = state.elements[state.index]
    if not current or not current.lootRollFrameIndex then return nil end

    local candidates = {}
    local index
    if dir == "LEFT" or dir == "RIGHT" then
        for index = 1, table.getn(state.elements) do
            local element = state.elements[index]
            if element.lootRollFrameIndex == current.lootRollFrameIndex and UsableElement(element) then
                table.insert(candidates, index)
            end
        end
    else
        local frameIndices = {}
        local lastFrameIndex = nil
        for index = 1, table.getn(state.elements) do
            local element = state.elements[index]
            if element.lootRollFrameIndex and element.lootRollFrameIndex ~= lastFrameIndex then
                table.insert(frameIndices, element.lootRollFrameIndex)
                lastFrameIndex = element.lootRollFrameIndex
            end
        end
        if table.getn(frameIndices) < 2 then return nil end

        local currentFramePosition = 1
        for index = 1, table.getn(frameIndices) do
            if frameIndices[index] == current.lootRollFrameIndex then
                currentFramePosition = index
                break
            end
        end
        if dir == "UP" then
            currentFramePosition = currentFramePosition + 1
        else
            currentFramePosition = currentFramePosition - 1
        end
        if currentFramePosition < 1 then currentFramePosition = table.getn(frameIndices) end
        if currentFramePosition > table.getn(frameIndices) then currentFramePosition = 1 end

        local targetFrameIndex = frameIndices[currentFramePosition]
        for index = 1, table.getn(state.elements) do
            local element = state.elements[index]
            if element.lootRollFrameIndex == targetFrameIndex and
               element.lootRollChoice == current.lootRollChoice and UsableElement(element) then
                state.index = index
                UpdateHighlight()
                return 1
            end
        end
        for index = 1, table.getn(state.elements) do
            local element = state.elements[index]
            if element.lootRollFrameIndex == targetFrameIndex and UsableElement(element) then
                state.index = index
                UpdateHighlight()
                return 1
            end
        end
        return nil
    end

    if table.getn(candidates) < 2 then return nil end
    local currentPosition = 1
    for index = 1, table.getn(candidates) do
        if candidates[index] == state.index then
            currentPosition = index
            break
        end
    end
    if dir == "LEFT" then
        currentPosition = currentPosition - 1
    else
        currentPosition = currentPosition + 1
    end
    if currentPosition < 1 then currentPosition = table.getn(candidates) end
    if currentPosition > table.getn(candidates) then currentPosition = 1 end
    state.index = candidates[currentPosition]
    UpdateHighlight()
    return 1
end

function DinoController_UIMoveDir(dir)
    if not state.active then
        RefreshElements()
    end
    if not state.elements or table.getn(state.elements) == 0 then return end
    if state.context == "lootroll" then
        -- Re-scan immediately on input: a timed-out frame must never remain
        -- the controller target until the periodic scan happens.
        RefreshElements()
        if state.context == "lootroll" and MoveGroupLootRoll(dir) then return end
    end
    local curElem = state.elements[state.index]
    if curElem and curElem.isScrollArea then
        if dir == "UP" or dir == "DOWN" then
            local scrolled = PerformScroll(curElem, dir)
            if scrolled then
                if state.context == "talent" then RefreshElements() end
                return
            end
        end
    end
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
    if Visible("LootFrame") and not HasVisibleGroupLootRoll() then
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
    if not element or not UsableElement(element) then return end
    if element.isScrollArea then return end

    local ok, err
    if element.action then
        ok, err = pcall(element.action)
    else
        ok, err = pcall(function() element.frame:Click(element.mouseButton) end)
    end
    if not ok then
        UIPrint("Dieses UI-Element konnte nicht ausgeloest werden: " .. tostring(err))
    end
    if state.context == "talent" then RefreshElements() end
    state.nextScan = 0
end

function DinoController_UICancel()
    if Visible("DropDownList1") then
        if DropDownList1 and DropDownList1.Hide then DropDownList1:Hide() end
        if DropDownList2 and DropDownList2.Hide then DropDownList2:Hide() end
        state.nextScan = 0
        return
    end
    if Visible("TaxiFrame") then
        if TaxiCloseButton and TaxiCloseButton.Click then
            TaxiCloseButton:Click("LeftButton")
        elseif HideUIPanel and TaxiFrame then
            HideUIPanel(TaxiFrame)
        end
        state.nextScan = 0
        return
    end
    if Visible("WorldMapFrame") then
        if ToggleWorldMap then ToggleWorldMap() elseif WorldMapFrame.Hide then WorldMapFrame:Hide() end
        state.nextScan = 0
        return
    end
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
navigationFrame:RegisterEvent("START_LOOT_ROLL")
navigationFrame:RegisterEvent("CANCEL_LOOT_ROLL")
navigationFrame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")
navigationFrame:RegisterEvent("UPDATE_WORLD_STATES")
navigationFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
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
navigationFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
navigationFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
navigationFrame:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
navigationFrame:RegisterEvent("AUCTION_BIDDER_LIST_UPDATE")
navigationFrame:RegisterEvent("AUCTION_OWNED_LIST_UPDATE")
navigationFrame:RegisterEvent("MAIL_SHOW")
navigationFrame:RegisterEvent("MAIL_INBOX_UPDATE")
navigationFrame:RegisterEvent("MAIL_CLOSED")
navigationFrame:RegisterEvent("PET_STABLE_SHOW")
navigationFrame:RegisterEvent("PET_STABLE_UPDATE")
navigationFrame:RegisterEvent("PET_STABLE_UPDATE_PAPERDOLL")
navigationFrame:RegisterEvent("PET_STABLE_CLOSED")
navigationFrame:RegisterEvent("UNIT_PET")
navigationFrame:RegisterEvent("TAXIMAP_OPENED")
navigationFrame:RegisterEvent("TAXIMAP_CLOSED")
navigationFrame:RegisterEvent("QUEST_LOG_UPDATE")
navigationFrame:RegisterEvent("WORLD_MAP_UPDATE")
navigationFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
navigationFrame:RegisterEvent("SPELLS_CHANGED")
navigationFrame:SetScript("OnEvent", function()
    if event == "MERCHANT_SHOW" then
        state.pendingMerchantBagFocus = 1
        OpenAllBags(1)
    elseif event == "MERCHANT_CLOSED" then
        state.pendingMerchantBagFocus = nil
        CloseAllBags()
    elseif event == "BANKFRAME_OPENED" then
        state.pendingBankFocus = 1
    elseif event == "BANKFRAME_CLOSED" then
        state.pendingBankFocus = nil
    elseif event == "TAXIMAP_CLOSED" and state.context == "taxi" then
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
