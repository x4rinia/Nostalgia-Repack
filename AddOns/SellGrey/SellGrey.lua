-- SellGrey for Vanilla WoW 1.12.1 (Nostalgia Edition)
local function IsGreyItem(bag, slot)
    local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
    if not texture then return false end
    if quality and quality == 0 then
        return true
    end
    local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
    if link then
        if string.find(string.lower(link), "9d9d9d") then
            return true
        end
        local _, _, itemID = string.find(link, "item:(%d+)")
        if itemID and GetItemInfo then
            local _, _, itemQuality = GetItemInfo(tonumber(itemID))
            if itemQuality and itemQuality == 0 then
                return true
            end
        end
        if GetItemInfo then
            local _, _, itemQuality = GetItemInfo(link)
            if itemQuality and itemQuality == 0 then
                return true
            end
        end
    end
    return false
end

local function SellAllGreyItems()
    if not MerchantFrame or not MerchantFrame:IsVisible() then return 0 end
    if ClearCursor then ClearCursor() end
    local totalSold = 0
    local bag, slot
    for bag = 0, 4 do
        local numSlots = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, numSlots do
            if IsGreyItem(bag, slot) then
                local texture, itemCount, locked = GetContainerItemInfo(bag, slot)
                if texture and not locked then
                    UseContainerItem(bag, slot)
                    totalSold = totalSold + 1
                end
            end
        end
    end
    if totalSold > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[SellGrey]|r " .. totalSold .. " gray items sold.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[SellGrey]|r No gray items to sell.")
    end
    return totalSold
end

local frame = CreateFrame("Frame", "SellGreyFrame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function()
    if event == "MERCHANT_SHOW" then
        local button = getglobal("MerchantSellJunkButton")
        if not button and CreateFrame then
            button = CreateFrame("Button", "MerchantSellJunkButton", MerchantFrame, "UIPanelButtonTemplate")
            if button then
                button:SetWidth(80)
                button:SetHeight(20)
                button:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -45, -40)
                button:SetText("SellGrey")
                button:SetScript("OnClick", function()
                    SellAllGreyItems()
                end)
            end
        end
    end
end)

SLASH_SELLGREY1 = "/sellgrey"
SLASH_SELLGREY2 = "/sg"
SlashCmdList["SELLGREY"] = function()
    SellAllGreyItems()
end
