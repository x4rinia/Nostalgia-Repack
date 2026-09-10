-- Vanilla 1.1.12 Ingame-Uhr unten rechts, ein-/ausschaltbar
local frame = CreateFrame("Frame", "VanillaClock", UIParent)
frame:SetWidth(80)
frame:SetHeight(20)
frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10) -- unten rechts

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetAllPoints(frame)

-- Funktion zum Updaten der Uhr
local function UpdateClock()
    text:SetText(date("%H:%M:%S"))
end

frame:SetScript("OnUpdate", function(self, elapsed)
    UpdateClock()
end)

-- Uhr standardmäßig sichtbar
frame:Show()
local clockVisible = true

-- Chat-Befehl, um Uhr ein-/auszuschalten
SLASH_CLOCK1 = "/clock"
SlashCmdList["CLOCK"] = function(msg)
    if clockVisible then
        frame:Hide()
        clockVisible = false
        DEFAULT_CHAT_FRAME:AddMessage("Clock hidden")
    else
        frame:Show()
        clockVisible = true
        DEFAULT_CHAT_FRAME:AddMessage("Clock shown")
    end
end
