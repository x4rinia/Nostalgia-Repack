local objects = {}
table.getn = table.getn or function(value) return #value end

local function NewObject(name, visible, x, y)
    local object = {
        name = name,
        visible = visible,
        enabled = 1,
        x = x or 100,
        y = y or 100,
        scripts = {},
        clickCount = 0
    }
    function object:GetName() return self.name end
    function object:IsVisible() return self.visible end
    function object:IsEnabled() return self.enabled end
    function object:GetCenter() return self.x, self.y end
    function object:GetParent() return self.parent end
    function object:SetParent(parent) self.parent = parent end
    function object:GetFrameLevel() return 1 end
    function object:SetFrameLevel() end
    function object:SetFrameStrata() end
    function object:EnableMouse() end
    function object:CreateTexture()
        return NewObject(nil, true)
    end
    function object:SetTexture() end
    function object:SetVertexColor() end
    function object:SetHeight() end
    function object:SetWidth() end
    function object:SetPoint(_, target) self.anchorTarget = target end
    function object:ClearAllPoints() self.anchorTarget = nil end
    function object:Show() self.visible = true end
    function object:Hide() self.visible = false end
    function object:SetScript(kind, script) self.scripts[kind] = script end
    function object:GetScript(kind) return self.scripts[kind] end
    function object:RegisterEvent() end
    function object:GetChildren() end
    function object:GetObjectType() return "Button" end
    function object:GetID() return self.id or 1 end
    function object:Click() self.clickCount = self.clickCount + 1 end
    if name then objects[name] = object; _G[name] = object end
    return object
end

function getglobal(name) return objects[name] or _G[name] end
function CreateFrame(_, name, parent)
    local frame = NewObject(name, false)
    frame.parent = parent
    return frame
end

UIParent = NewObject("UIParent", true, 500, 400)
GameTooltip = { Hide = function() end }
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) error(message) end }
DinoControllerDB = { controllerEnabled = 1, uiEnabled = 1 }
DinoControllerBridgeConfig = { ButtonMappings = {} }
NUM_CONTAINER_FRAMES = 1
NUM_GROUP_LOOT_FRAMES = 4
function GetBindingAction() return "" end
function SetBinding() end
function DinoController_SetUIMode() end
function DinoController_ApplyButtonLayout() end
function UnitClass() return "Krieger", "WARRIOR" end

local battlefieldLeaves = 0
local selectedScoreTab = nil
function LeaveBattlefield() battlefieldLeaves = battlefieldLeaves + 1 end
function WorldStateScoreFrameTab_OnClick(tab) selectedScoreTab = tab:GetID() end
function HideUIPanel(frame) frame:Hide() end

local rolls = {}
function RollOnLoot(rollID, rollType)
    table.insert(rolls, { rollID, rollType })
end

local bag = NewObject("ContainerFrame1", true, 50, 50)
bag.id = 0
local bagItem = NewObject("ContainerFrame1Item1", true, 60, 60)
bagItem.parent = bag
local lootFrame = NewObject("LootFrame", false, 300, 300)

local scoreFrame = NewObject("WorldStateScoreFrame", false, 500, 400)
local scoreLeave = NewObject("WorldStateScoreFrameLeaveButton", false, 470, 100)
local scoreClose = NewObject("WorldStateScoreFrameCloseButton", false, 700, 700)
scoreLeave.parent = scoreFrame
scoreClose.parent = scoreFrame
for index = 1, 3 do
    local tab = NewObject("WorldStateScoreFrameTab" .. index, false, 300 + index * 100, 90)
    tab.id = index
    tab.parent = scoreFrame
end
local scoreScroll = NewObject("WorldStateScoreScrollFrame", false, 500, 400)
scoreScroll.parent = scoreFrame

local function SetScoreVisible(visible, ended)
    scoreFrame.visible = visible
    scoreLeave.visible = visible and ended
    scoreClose.visible = visible
    for index = 1, 3 do objects["WorldStateScoreFrameTab" .. index].visible = visible end
end

local function NewRollFrame(index, rollID, visible, y)
    local frame = NewObject("GroupLootFrame" .. index, visible, 400, y)
    frame.rollID = rollID
    for _, suffix in ipairs({ "RollButton", "GreedButton", "PassButton" }) do
        local button = NewObject(frame.name .. suffix, visible, 400, y)
        button.parent = frame
    end
    return frame
end

local roll1 = NewRollFrame(1, 101, false, 100)
local roll2 = NewRollFrame(2, 202, false, 200)

dofile("addons/DinoController/DinoControllerUI.lua")
local navigation = objects.DinoControllerUINavigationFrame
local highlight = objects.DinoControllerUIHighlight
local function Scan()
    this = navigation
    arg1 = 1
    navigation.scripts.OnUpdate()
end

Scan()
assert(highlight.anchorTarget == bagItem, "normal UI focus was not established")

roll1.visible = true
roll2.visible = true
lootFrame.visible = true
for _, suffix in ipairs({ "RollButton", "GreedButton", "PassButton" }) do
    objects[roll1.name .. suffix].visible = true
    objects[roll2.name .. suffix].visible = true
end
Scan()
assert(highlight.anchorTarget == objects.GroupLootFrame1RollButton, "first roll did not receive focus")
DinoController_UIActivate()
assert(#rolls == 1 and rolls[1][1] == 101 and rolls[1][2] == 1, "confirm did not call native need")

DinoController_UIMoveDir("RIGHT")
assert(highlight.anchorTarget == objects.GroupLootFrame1GreedButton, "right did not select greed")
DinoController_UIActivate()
assert(#rolls == 2 and rolls[2][1] == 101 and rolls[2][2] == 2, "confirm did not call native greed")
DinoController_UIMoveDir("RIGHT")
assert(highlight.anchorTarget == objects.GroupLootFrame1PassButton, "right did not select pass")
DinoController_UIMoveDir("UP")
assert(highlight.anchorTarget == objects.GroupLootFrame2PassButton, "up did not switch roll frames")
DinoController_UIActivate()
assert(#rolls == 3 and rolls[3][1] == 202 and rolls[3][2] == 0, "confirm did not call native pass")
assert(objects.GroupLootFrame1RollButton.clickCount == 0, "need used a simulated click")
assert(objects.GroupLootFrame1GreedButton.clickCount == 0, "greed used a simulated click")
assert(objects.GroupLootFrame2PassButton.clickCount == 0, "loot roll used a simulated click")

roll2.visible = false
for _, suffix in ipairs({ "RollButton", "GreedButton", "PassButton" }) do
    objects[roll2.name .. suffix].visible = false
end
Scan()
assert(highlight.anchorTarget == objects.GroupLootFrame1PassButton, "closed roll did not advance to an open roll")

roll1.visible = false
lootFrame.visible = false
for _, suffix in ipairs({ "RollButton", "GreedButton", "PassButton" }) do
    objects[roll1.name .. suffix].visible = false
end
Scan()
assert(highlight.anchorTarget == bagItem, "previous UI focus was not restored")

SetScoreVisible(true, true)
Scan()
assert(highlight.anchorTarget == scoreLeave, "BG end screen did not initially focus Leave")
DinoController_UIActivate()
assert(battlefieldLeaves == 1, "BG Leave did not call native LeaveBattlefield")
assert(scoreLeave.clickCount == 0, "BG Leave used a simulated click")
SetScoreVisible(false, false)
Scan()
assert(highlight.anchorTarget == bagItem, "focus was not returned after leaving the BG")

SetScoreVisible(true, false)
Scan()
assert(highlight.anchorTarget == objects.WorldStateScoreFrameTab1, "open scoreboard did not focus its first native tab")
DinoController_UIActivate()
assert(selectedScoreTab == 1, "scoreboard tab did not use the native tab function")
assert(objects.WorldStateScoreFrameTab1.clickCount == 0, "scoreboard tab used a simulated click")
DinoController_UIMove(3)
assert(highlight.anchorTarget == scoreClose, "scoreboard close button was not navigable")
DinoController_UIActivate()
assert(not scoreFrame.visible, "scoreboard close did not use HideUIPanel")
assert(scoreClose.clickCount == 0, "scoreboard close used a simulated click")
Scan()
assert(highlight.anchorTarget == bagItem, "focus was not returned after closing the scoreboard")

print("loot roll and battleground scoreboard navigation tests passed")
