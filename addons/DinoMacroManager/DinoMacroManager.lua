-- DinoMacroManager 1.0.0 - eigenstaendiges WoW-1.12.1-Addon
-- Author: x4rinia

BINDING_HEADER_DINOMACROMANAGER = "DinoMacroManager";
BINDING_NAME_DMM_SLOT_1 = "Zauberkette 1 ausloesen";
BINDING_NAME_DMM_SLOT_2 = "Zauberkette 2 ausloesen";
BINDING_NAME_DMM_SLOT_3 = "Zauberkette 3 ausloesen";
BINDING_NAME_DMM_SLOT_4 = "Zauberkette 4 ausloesen";
BINDING_NAME_DMM_SLOT_5 = "Zauberkette 5 ausloesen";
BINDING_NAME_DMM_SLOT_6 = "Zauberkette 6 ausloesen";
BINDING_NAME_DMM_SLOT_7 = "Zauberkette 7 ausloesen";
BINDING_NAME_DMM_SLOT_8 = "Zauberkette 8 ausloesen";
BINDING_NAME_DMM_SLOT_9 = "Zauberkette 9 ausloesen";
BINDING_NAME_DMM_SLOT_10 = "Zauberkette 10 ausloesen";
BINDING_NAME_DMM_SLOT_11 = "Zauberkette 11 ausloesen";
BINDING_NAME_DMM_SLOT_12 = "Zauberkette 12 ausloesen";
BINDING_NAME_DMM_SLOT_13 = "Zauberkette 13 ausloesen";
BINDING_NAME_DMM_SLOT_14 = "Zauberkette 14 ausloesen";

local DMM_SLOT_COUNT = 14;
local DMM_MIN_SPELLS = 2;
local DMM_MAX_SPELLS = 4;
local DMM_DEFAULT_RESET = 10;
local DMM_SUCCESS_DELAY = 0.12;
local DMM_PENDING_TIMEOUT = 30;
local DMM_BOOKTYPE = BOOKTYPE_SPELL or "spell";
local DMM_QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark";

local dmmMainFrame = nil;
local dmmEditorFrame = nil;
local dmmSlotButtons = {};
local dmmEditorFields = {};
local dmmEditorSlot = nil;
local dmmEditorSpells = {};
local dmmPendingCast = nil;
local dmmUpdateElapsed = 0;
local dmmPickedSpellIndex = nil;
local dmmPickedSpellBookType = nil;
local dmmPickupSpellHookInstalled = nil;
local DMM_UpdateSlotMacroIcon = nil;
local DMM_PickupSlotMacro = nil;
local DMM_UpdateBlizzardCooldowns = nil;

-- Der eingesetzte 1.12.1-Client exportiert GetCursorInfo() nicht. Das
-- originale SpellBookFrame nimmt Zauber jedoch immer ueber PickupSpell()
-- auf. Der Wrapper merkt sich genau diese Spellbook-Referenz und delegiert
-- den eigentlichen Cursor-Aufruf unveraendert an Blizzard weiter.
local function DMM_InstallPickupSpellHook()
    if dmmPickupSpellHookInstalled or type(PickupSpell) ~= "function" then
        return;
    end
    local originalPickupSpell = PickupSpell;
    PickupSpell = function(spellIndex, bookType)
        dmmPickedSpellIndex = spellIndex;
        dmmPickedSpellBookType = bookType or DMM_BOOKTYPE;
        return originalPickupSpell(spellIndex, bookType);
    end;
    dmmPickupSpellHookInstalled = 1;
end

local function DMM_Chat(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDinoMacroManager:|r " .. text);
    end
end

local function DMM_SetStatus(text, isError)
    if not dmmMainFrame or not dmmMainFrame.status then
        return;
    end
    dmmMainFrame.status:SetText(text or "");
    if isError then
        dmmMainFrame.status:SetTextColor(1, 0.3, 0.3);
    else
        dmmMainFrame.status:SetTextColor(0.55, 0.85, 1);
    end
end

local function DMM_SetEditorStatus(text, isError)
    if not dmmEditorFrame or not dmmEditorFrame.status then
        return;
    end
    dmmEditorFrame.status:SetText(text or "");
    if isError then
        dmmEditorFrame.status:SetTextColor(1, 0.3, 0.3);
    else
        dmmEditorFrame.status:SetTextColor(0.5, 1, 0.5);
    end
end

local function DMM_NewSlot()
    return {
        name = "",
        current = 1,
        spells = {},
        resetSeconds = DMM_DEFAULT_RESET,
        resetOnTargetChange = nil
    };
end

local function DMM_InitializeDB()
    if type(DinoMacroManagerDB) ~= "table" then
        DinoMacroManagerDB = {};
    end
    if type(DinoMacroManagerDB.slots) ~= "table" then
        DinoMacroManagerDB.slots = {};
    end
    if type(DinoMacroManagerDB.position) ~= "table" then
        DinoMacroManagerDB.position = {
            point = "CENTER", relativePoint = "CENTER", x = 0, y = 0
        };
    end
    -- Migration der bisherigen globalen Resetzeit auf jeden einzelnen Slot.
    local oldResetSeconds = tonumber(DinoMacroManagerDB.resetSeconds);
    if not oldResetSeconds or oldResetSeconds < 0 or oldResetSeconds > 3600 then
        oldResetSeconds = DMM_DEFAULT_RESET;
    end
    DinoMacroManagerDB.version = 2;

    for i = 1, DMM_SLOT_COUNT do
        local slot = DinoMacroManagerDB.slots[i];
        if type(slot) ~= "table" then
            slot = DMM_NewSlot();
            DinoMacroManagerDB.slots[i] = slot;
        end
        if type(slot.spells) ~= "table" then
            slot.spells = {};
        end
        if type(slot.name) ~= "string" then
            slot.name = "";
        end
        local slotResetSeconds = tonumber(slot.resetSeconds);
        if not slotResetSeconds or slotResetSeconds < 0 or slotResetSeconds > 3600 then
            slotResetSeconds = oldResetSeconds;
        end
        slot.resetSeconds = slotResetSeconds;
        slot.resetOnTargetChange = slot.resetOnTargetChange and 1 or nil;
        slot.current = tonumber(slot.current) or 1;
        if slot.current < 1 or slot.current > table.getn(slot.spells) then
            slot.current = 1;
        end
        -- GetTime() ist sitzungsbezogen. Ein Relog gilt deshalb als Zeitreset.
        slot.lastUsed = nil;
        slot.invalid = nil;
    end
    DinoMacroManagerDB.resetSeconds = nil;
end

local function DMM_CopySpell(spell)
    if not spell then
        return nil;
    end
    return {
        name = spell.name,
        rank = spell.rank,
        bookIndex = spell.bookIndex,
        bookType = spell.bookType,
        icon = spell.icon
    };
end

local function DMM_SpellMatches(bookIndex, bookType, spell)
    local name, rank = GetSpellName(bookIndex, bookType);
    if not name or name ~= spell.name then
        return nil;
    end
    rank = rank or "";
    if rank ~= (spell.rank or "") then
        return nil;
    end
    return 1;
end

local function DMM_ResolveSpell(spell)
    if type(spell) ~= "table" or type(spell.name) ~= "string" then
        return nil;
    end
    local bookType = spell.bookType or DMM_BOOKTYPE;
    local oldIndex = tonumber(spell.bookIndex);
    if oldIndex and DMM_SpellMatches(oldIndex, bookType, spell) then
        spell.bookIndex = oldIndex;
        spell.bookType = bookType;
        spell.icon = GetSpellTexture(oldIndex, bookType) or spell.icon;
        return oldIndex;
    end

    local numTabs = GetNumSpellTabs();
    for tab = 1, numTabs do
        local tabName, tabTexture, offset, numSpells = GetSpellTabInfo(tab);
        if offset and numSpells then
            for index = offset + 1, offset + numSpells do
                if DMM_SpellMatches(index, bookType, spell) then
                    spell.bookIndex = index;
                    spell.bookType = bookType;
                    spell.icon = GetSpellTexture(index, bookType) or spell.icon;
                    return index;
                end
            end
        end
    end
    return nil;
end

local function DMM_ApplyTimeReset(slot)
    if not slot or not slot.lastUsed or slot.current == 1 then
        return nil;
    end
    local resetSeconds = tonumber(slot.resetSeconds) or DMM_DEFAULT_RESET;
    if resetSeconds <= 0 then
        return nil;
    end
    if GetTime() - slot.lastUsed >= resetSeconds then
        slot.current = 1;
        slot.lastUsed = nil;
        return 1;
    end
    return nil;
end

local function DMM_UpdateSlotButton(index)
    local button = dmmSlotButtons[index];
    if not button or not DinoMacroManagerDB then
        return;
    end
    local slot = DinoMacroManagerDB.slots[index];
    DMM_ApplyTimeReset(slot);
    local count = table.getn(slot.spells);
    if slot.current < 1 or slot.current > count then
        slot.current = 1;
    end

    button.number:SetText(tostring(index));
    if slot.name ~= "" then
        button.chainName:SetText(slot.name);
    else
        button.chainName:SetText("Slot " .. index);
    end

    local spell = slot.spells[slot.current];
    if not spell then
        button.icon:SetTexture(DMM_QUESTION_ICON);
        button.icon:SetVertexColor(0.45, 0.45, 0.45);
        button.step:SetText("Leer");
        button:SetBackdropBorderColor(0.25, 0.45, 0.65, 0.8);
        slot.invalid = nil;
        if button.cooldown then
            CooldownFrame_SetTimer(button.cooldown, 0, 0, 0);
        end
        if DMM_UpdateSlotMacroIcon then
            DMM_UpdateSlotMacroIcon(index, DMM_QUESTION_ICON);
        end
        return;
    end

    local bookIndex = DMM_ResolveSpell(spell);
    button.icon:SetTexture(spell.icon or DMM_QUESTION_ICON);
    if not bookIndex then
        button.icon:SetVertexColor(1, 0.25, 0.25);
        button.step:SetText("Ungueltig");
        button:SetBackdropBorderColor(1, 0.15, 0.15, 1);
        slot.invalid = 1;
        if button.cooldown then
            CooldownFrame_SetTimer(button.cooldown, 0, 0, 0);
        end
    else
        button.icon:SetVertexColor(1, 1, 1);
        button.step:SetText(slot.current .. "/" .. count);
        button:SetBackdropBorderColor(0.25, 0.65, 0.95, 1);
        slot.invalid = nil;
        if button.cooldown then
            local start, duration, enable = GetSpellCooldown(bookIndex, spell.bookType or DMM_BOOKTYPE);
            if start and duration and duration > 0 then
                CooldownFrame_SetTimer(button.cooldown, start, duration, enable);
            else
                CooldownFrame_SetTimer(button.cooldown, 0, 0, 0);
            end
        end
    end
    if DMM_UpdateSlotMacroIcon then
        DMM_UpdateSlotMacroIcon(index, spell.icon or DMM_QUESTION_ICON);
    end
end

local function DMM_UpdateAllSlots()
    if not DinoMacroManagerDB then
        return;
    end
    for i = 1, DMM_SLOT_COUNT do
        DMM_UpdateSlotButton(i);
    end
    if DMM_UpdateBlizzardCooldowns then
        DMM_UpdateBlizzardCooldowns();
    end
end

local function DMM_UpdateEditorFields()
    for i = 1, DMM_MAX_SPELLS do
        local field = dmmEditorFields[i];
        local spell = dmmEditorSpells[i];
        if spell then
            field.icon:SetTexture(spell.icon or DMM_QUESTION_ICON);
            field.icon:SetVertexColor(1, 1, 1);
            local label = spell.name or "Unbekannt";
            if spell.rank and spell.rank ~= "" then
                label = label .. " (" .. spell.rank .. ")";
            end
            field.text:SetText(label);
            field.hint:SetText("Rechtsklick: entfernen");
            field:SetBackdropBorderColor(0.25, 0.65, 0.95, 1);
        else
            field.icon:SetTexture(DMM_QUESTION_ICON);
            field.icon:SetVertexColor(0.35, 0.35, 0.35);
            field.text:SetText("Zauber " .. i .. ": hier ablegen");
            field.hint:SetText("Aus dem normalen Zauberbuch ziehen");
            field:SetBackdropBorderColor(0.3, 0.4, 0.5, 1);
        end
    end
end

local function DMM_RemoveEditorSpell(index)
    if not dmmEditorSpells[index] then
        return;
    end
    for i = index, DMM_MAX_SPELLS - 1 do
        dmmEditorSpells[i] = dmmEditorSpells[i + 1];
    end
    dmmEditorSpells[DMM_MAX_SPELLS] = nil;
    DMM_UpdateEditorFields();
    DMM_SetEditorStatus("Zauberplatz entfernt.", nil);
end

local function DMM_ReceiveSpell(index)
    local bookIndex, bookType;
    if type(GetCursorInfo) == "function" then
        local cursorType;
        cursorType, bookIndex, bookType = GetCursorInfo();
        if cursorType ~= "spell" then
            DMM_SetEditorStatus("Bitte einen Spielerzauber aus dem Zauberbuch ablegen.", 1);
            return;
        end
    else
        if type(CursorHasSpell) ~= "function" or not CursorHasSpell() then
            DMM_SetEditorStatus("Bitte einen Spielerzauber aus dem Zauberbuch ablegen.", 1);
            return;
        end
        bookIndex = dmmPickedSpellIndex;
        bookType = dmmPickedSpellBookType;
        if not bookIndex then
            DMM_SetEditorStatus("Die Spellbook-Referenz konnte nicht gelesen werden.", 1);
            return;
        end
    end
    bookType = bookType or DMM_BOOKTYPE;
    if bookType ~= DMM_BOOKTYPE then
        DMM_SetEditorStatus("Pet-Zauber werden nicht unterstuetzt.", 1);
        return;
    end
    local name, rank = GetSpellName(bookIndex, bookType);
    if not name then
        DMM_SetEditorStatus("Der abgelegte Zauber konnte nicht gelesen werden.", 1);
        return;
    end
    if IsSpellPassive and IsSpellPassive(bookIndex, bookType) then
        DMM_SetEditorStatus("Passive Zauber koennen nicht ausgeloest werden.", 1);
        return;
    end
    dmmEditorSpells[index] = {
        name = name,
        rank = rank or "",
        bookIndex = bookIndex,
        bookType = bookType,
        icon = GetSpellTexture(bookIndex, bookType)
    };
    ClearCursor();
    dmmPickedSpellIndex = nil;
    dmmPickedSpellBookType = nil;
    DMM_UpdateEditorFields();
    DMM_SetEditorStatus(name .. " gespeichert (noch nicht uebernommen).", nil);
end

local function DMM_OpenEditor(index)
    if not dmmEditorFrame then
        return;
    end
    dmmEditorSlot = index;
    dmmEditorSpells = {};
    local slot = DinoMacroManagerDB.slots[index];
    for i = 1, DMM_MAX_SPELLS do
        dmmEditorSpells[i] = DMM_CopySpell(slot.spells[i]);
    end
    dmmEditorFrame.title:SetText("Slot " .. index .. " bearbeiten");
    dmmEditorFrame.nameEdit:SetText(slot.name or "");
    dmmEditorFrame.resetEdit:SetText(tostring(slot.resetSeconds or DMM_DEFAULT_RESET));
    dmmEditorFrame.targetResetCheck:SetChecked(slot.resetOnTargetChange and 1 or nil);
    DMM_SetEditorStatus("2 bis 4 Zauber aus dem Zauberbuch ablegen.", nil);
    DMM_UpdateEditorFields();
    dmmEditorFrame:Show();
    dmmEditorFrame:Raise();
end

local function DMM_SaveEditor()
    if not dmmEditorSlot then
        return;
    end
    local compact = {};
    for i = 1, DMM_MAX_SPELLS do
        if dmmEditorSpells[i] then
            table.insert(compact, DMM_CopySpell(dmmEditorSpells[i]));
        end
    end
    local count = table.getn(compact);
    if count < DMM_MIN_SPELLS or count > DMM_MAX_SPELLS then
        DMM_SetEditorStatus("Eine Kette braucht mindestens 2 und maximal 4 Zauber.", 1);
        return;
    end
    for i = 1, count do
        if not DMM_ResolveSpell(compact[i]) then
            DMM_SetEditorStatus("Zauber " .. i .. " ist nicht mehr im Zauberbuch.", 1);
            return;
        end
    end
    local resetSeconds = tonumber(dmmEditorFrame.resetEdit:GetText());
    if not resetSeconds or resetSeconds < 0 or resetSeconds > 3600 then
        DMM_SetEditorStatus("Resetzeit muss zwischen 0 und 3600 Sekunden liegen.", 1);
        return;
    end
    local slot = DinoMacroManagerDB.slots[dmmEditorSlot];
    slot.name = dmmEditorFrame.nameEdit:GetText() or "";
    slot.spells = compact;
    slot.resetSeconds = resetSeconds;
    slot.resetOnTargetChange = dmmEditorFrame.targetResetCheck:GetChecked() and 1 or nil;
    slot.current = 1;
    slot.lastUsed = nil;
    slot.invalid = nil;
    DMM_UpdateAllSlots();
    DMM_SetStatus("Slot " .. dmmEditorSlot .. " gespeichert.", nil);
    dmmEditorFrame:Hide();
end

local function DMM_ClearEditorSlot()
    if not dmmEditorSlot then
        return;
    end
    DinoMacroManagerDB.slots[dmmEditorSlot] = DMM_NewSlot();
    dmmEditorSpells = {};
    dmmEditorFrame.nameEdit:SetText("");
    dmmEditorFrame.resetEdit:SetText(tostring(DMM_DEFAULT_RESET));
    dmmEditorFrame.targetResetCheck:SetChecked(nil);
    DMM_UpdateEditorFields();
    DMM_UpdateAllSlots();
    DMM_SetEditorStatus("Der komplette Slot wurde geleert.", nil);
    DMM_SetStatus("Slot " .. dmmEditorSlot .. " geleert.", nil);
end

local function DMM_FindSlotMacro(index)
    if type(GetMacroInfo) ~= "function" then
        return nil;
    end
    local triggerBody = "/script DinoMacroManager_TriggerSlot(" .. index .. ")";
    local executeBody = "/script DinoMacroManager_ExecuteSlot(" .. index .. ")";
    for macroIndex = 1, 36 do
        local macroName, macroIcon, macroBody = GetMacroInfo(macroIndex);
        if macroName and (macroBody == triggerBody or macroBody == executeBody) then
            return macroIndex, macroName, macroIcon, macroBody;
        end
    end
    return nil;
end

local function DMM_FindMacroIconIndex(texture)
    if type(GetNumMacroIcons) ~= "function" or type(GetMacroIconInfo) ~= "function" then
        return 1;
    end
    local wanted = texture and string.lower(texture) or nil;
    local questionIndex = nil;
    local numIcons = GetNumMacroIcons();
    for iconIndex = 1, numIcons do
        local iconTexture = GetMacroIconInfo(iconIndex);
        if iconTexture then
            local lowered = string.lower(iconTexture);
            if wanted and lowered == wanted then
                return iconIndex;
            end
            if not questionIndex and string.find(lowered, "inv_misc_questionmark", 1, 1) then
                questionIndex = iconIndex;
            end
        end
    end
    return questionIndex or 1;
end

DMM_UpdateSlotMacroIcon = function(index, icon)
    if type(EditMacro) ~= "function" then
        return;
    end
    local macroIndex, macroName, macroIcon, macroBody = DMM_FindSlotMacro(index);
    if macroIndex and icon and macroIcon ~= icon then
        EditMacro(macroIndex, macroName, DMM_FindMacroIconIndex(icon), macroBody, 1, 1);
    end
end;

DMM_PickupSlotMacro = function()
    if not dmmEditorSlot then
        return;
    end
    if type(CreateMacro) ~= "function" or type(PickupMacro) ~= "function" then
        DMM_SetEditorStatus("Dieser Client stellt die Makro-APIs nicht bereit.", 1);
        return;
    end
    local index = dmmEditorSlot;
    local slot = DinoMacroManagerDB.slots[index];
    local spell = slot.spells[slot.current or 1];
    local icon = (spell and spell.icon) or DMM_QUESTION_ICON;
    local macroIndex = DMM_FindSlotMacro(index);
    if not macroIndex then
        local macroName = "DMM Slot " .. index;
        local macroBody = "/script DinoMacroManager_ExecuteSlot(" .. index .. ")";
        macroIndex = CreateMacro(macroName, DMM_FindMacroIconIndex(icon), macroBody, 1, 1);
        macroIndex = DMM_FindSlotMacro(index) or macroIndex;
    end
    if not macroIndex or macroIndex == 0 then
        DMM_SetEditorStatus("Kein freier charakterspezifischer Makroplatz.", 1);
        return;
    end
    ClearCursor();
    PickupMacro(macroIndex);
    DMM_SetEditorStatus("DMM Slot " .. index .. " liegt am Cursor: jetzt auf die Blizzard-Leiste ziehen.", nil);
end;

local function DMM_UpdateBlizzardButtonCooldown(button)
    if not button or type(ActionButton_GetPagedID) ~= "function" then
        return;
    end
    local actionSlot = ActionButton_GetPagedID(button);
    local actionText = actionSlot and GetActionText(actionSlot);
    local slotIndex = nil;
    if actionText then
        for i = 1, DMM_SLOT_COUNT do
            if actionText == "DMM Slot " .. i then
                slotIndex = i;
                break
            end
        end
    end

    local overlay = button.dmmMacroCooldown;
    if not slotIndex then
        if overlay then
            CooldownFrame_SetTimer(overlay, 0, 0, 0);
            overlay:Hide();
        end
        return;
    end

    if not overlay then
        overlay = CreateFrame("Model", button:GetName() .. "DMMCooldown", button, "CooldownFrameTemplate");
        overlay:SetWidth(36);
        overlay:SetHeight(36);
        overlay:SetPoint("CENTER", button, "CENTER", 0, 0);
        overlay:SetFrameLevel(button:GetFrameLevel() + 2);
        button.dmmMacroCooldown = overlay;
    end

    local slot = DinoMacroManagerDB.slots[slotIndex];
    local spell = slot and slot.spells[slot.current or 1];
    local bookIndex = spell and DMM_ResolveSpell(spell);
    if bookIndex then
        local start, duration, enable = GetSpellCooldown(bookIndex, spell.bookType or DMM_BOOKTYPE);
        if start and duration and duration > 0 then
            CooldownFrame_SetTimer(overlay, start, duration, enable);
            overlay:Show();
            return;
        end
    end
    CooldownFrame_SetTimer(overlay, 0, 0, 0);
    overlay:Hide();
end

DMM_UpdateBlizzardCooldowns = function()
    local prefixes = {
        "ActionButton",
        "BonusActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarLeftButton",
        "MultiBarRightButton"
    };
    for prefixIndex = 1, table.getn(prefixes) do
        for buttonIndex = 1, 12 do
            DMM_UpdateBlizzardButtonCooldown(getglobal(prefixes[prefixIndex] .. buttonIndex));
        end
    end
end;

local function DMM_ConfirmPendingCast()
    local pending = dmmPendingCast;
    if not pending then
        return;
    end
    local slot = DinoMacroManagerDB.slots[pending.slotIndex];
    if not slot or slot.current ~= pending.step or slot.spells[pending.step] ~= pending.spell then
        dmmPendingCast = nil;
        return;
    end
    local count = table.getn(slot.spells);
    slot.current = slot.current + 1;
    if slot.current > count then
        slot.current = 1;
    end
    slot.lastUsed = GetTime();
    dmmPendingCast = nil;
    DMM_UpdateSlotButton(pending.slotIndex);
    DMM_UpdateBlizzardCooldowns();
    DMM_SetStatus("Slot " .. pending.slotIndex .. ": naechster Schritt " .. slot.current .. ".", nil);
end

function DinoMacroManager_TriggerSlot(index)
    index = tonumber(index);
    if not index or index < 1 or index > DMM_SLOT_COUNT or not DinoMacroManagerDB then
        return;
    end
    local slot = DinoMacroManagerDB.slots[index];
    DMM_ApplyTimeReset(slot);
    local count = table.getn(slot.spells);
    if count < DMM_MIN_SPELLS or count > DMM_MAX_SPELLS then
        DMM_SetStatus("Slot " .. index .. " ist leer oder unvollstaendig.", 1);
        DMM_OpenEditor(index);
        return;
    end
    if dmmPendingCast then
        DMM_SetStatus("Ein Zauber wartet noch auf seine Cast-Bestaetigung.", 1);
        return;
    end
    if slot.current < 1 or slot.current > count then
        slot.current = 1;
    end
    local spell = slot.spells[slot.current];
    local bookIndex = DMM_ResolveSpell(spell);
    if not bookIndex then
        slot.invalid = 1;
        DMM_UpdateSlotButton(index);
        DMM_SetStatus("Slot " .. index .. ": aktueller Zauber ist ungueltig.", 1);
        return;
    end

    local start, duration, enabled = GetSpellCooldown(bookIndex, spell.bookType or DMM_BOOKTYPE);
    if enabled == 0 or (start and duration and duration > 0 and start + duration > GetTime()) then
        DMM_SetStatus("Slot " .. index .. ": aktueller Zauber ist noch nicht bereit.", 1);
        return;
    end

    local castName = spell.name;
    if spell.rank and spell.rank ~= "" then
        castName = castName .. "(" .. spell.rank .. ")";
    end
    dmmPendingCast = {
        slotIndex = index,
        step = slot.current,
        spell = spell,
        startedAt = GetTime(),
        successAt = nil
    };
    CastSpellByName(castName);
end

-- Oeffentliches API fuer optionale Integrationen. Fuehrt exakt einen Schritt
-- aus und haelt dieselben Erfolgs-, Cooldown- und Fehlerregeln wie der HUD-Slot ein.
function DinoMacroManager_ExecuteSlot(slot)
    DinoMacroManager_TriggerSlot(slot);
end

local function DMM_SavePosition()
    if not dmmMainFrame or not DinoMacroManagerDB then
        return;
    end
    local point, relativeTo, relativePoint, x, y = dmmMainFrame:GetPoint();
    DinoMacroManagerDB.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0
    };
end

local function DMM_RestorePosition()
    local pos = DinoMacroManagerDB.position;
    dmmMainFrame:ClearAllPoints();
    dmmMainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0);
end

local function DMM_ResetPosition()
    DinoMacroManagerDB.position = {
        point = "CENTER", relativePoint = "CENTER", x = 0, y = 0
    };
    DMM_RestorePosition();
    DMM_SetStatus("Fensterposition zurueckgesetzt.", nil);
end

local function DMM_CreateSlotButton(index)
    local button = CreateFrame("Button", "DinoMacroManagerSlot" .. index, dmmMainFrame);
    button:SetWidth(68);
    button:SetHeight(80);
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = 1, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    });
    button:SetBackdropColor(0.03, 0.06, 0.11, 0.95);
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp");

    local col = math.mod(index - 1, 7);
    local row = math.floor((index - 1) / 7);
    button:SetPoint("TOPLEFT", dmmMainFrame, "TOPLEFT", 14 + col * 74, -40 - row * 84);

    button.number = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    button.number:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -5);
    button.number:SetText(tostring(index));

    button.icon = button:CreateTexture(nil, "ARTWORK");
    button.icon:SetWidth(38);
    button.icon:SetHeight(38);
    button.icon:SetPoint("TOP", button, "TOP", 0, -18);
    button.icon:SetTexture(DMM_QUESTION_ICON);

    button.cooldown = CreateFrame("Model", "DinoMacroManagerSlotCooldown" .. index, button, "CooldownFrameTemplate");
    button.cooldown:SetWidth(38);
    button.cooldown:SetHeight(38);
    button.cooldown:SetPoint("TOP", button, "TOP", 0, -18);

    button.step = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    button.step:SetPoint("TOPRIGHT", button, "TOPRIGHT", -5, -5);

    button.chainName = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    button.chainName:SetWidth(60);
    button.chainName:SetHeight(14);
    button.chainName:SetPoint("BOTTOM", button, "BOTTOM", 0, 5);

    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
    button:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            DMM_OpenEditor(index);
        else
            DinoMacroManager_TriggerSlot(index);
        end
    end);
    button:SetScript("OnEnter", function()
        local slot = DinoMacroManagerDB.slots[index];
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT");
        GameTooltip:SetText("Slot " .. index .. (slot.name ~= "" and (" - " .. slot.name) or ""));
        local spell = slot.spells[slot.current];
        if spell then
            GameTooltip:AddLine("Naechster Zauber: " .. spell.name, 1, 1, 1);
        end
        GameTooltip:AddLine("Linksklick: ausloesen", 0.6, 0.85, 1);
        GameTooltip:AddLine("Rechtsklick: bearbeiten", 0.6, 0.85, 1);
        GameTooltip:Show();
    end);
    button:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    dmmSlotButtons[index] = button;
end

local function DMM_CreateEditor()
    local frame = CreateFrame("Frame", "DinoMacroManagerEditor", UIParent);
    frame:SetWidth(430);
    frame:SetHeight(420);
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
    frame:SetFrameStrata("DIALOG");
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = 1, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    });
    frame:EnableMouse(1);
    frame:SetMovable(1);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", function() this:StartMoving(); end);
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing(); end);
    frame:Hide();

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    frame.title:SetPoint("TOP", frame, "TOP", 0, -18);

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5);

    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -52);
    nameLabel:SetText("Name:");

    frame.nameEdit = CreateFrame("EditBox", "DinoMacroManagerNameEdit", frame, "InputBoxTemplate");
    frame.nameEdit:SetWidth(285);
    frame.nameEdit:SetHeight(24);
    frame.nameEdit:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0);
    frame.nameEdit:SetAutoFocus(nil);
    frame.nameEdit:SetMaxLetters(20);

    for i = 1, DMM_MAX_SPELLS do
        local fieldIndex = i;
        local field = CreateFrame("Button", "DinoMacroManagerEditorSpell" .. i, frame);
        field:SetWidth(374);
        field:SetHeight(48);
        field:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -78 - (i - 1) * 52);
        field:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = 1, tileSize = 16, edgeSize = 10,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        });
        field:SetBackdropColor(0.03, 0.05, 0.09, 0.95);
        field:RegisterForDrag("LeftButton");
        field:RegisterForClicks("LeftButtonUp", "RightButtonUp");

        field.icon = field:CreateTexture(nil, "ARTWORK");
        field.icon:SetWidth(36);
        field.icon:SetHeight(36);
        field.icon:SetPoint("LEFT", field, "LEFT", 7, 0);

        field.text = field:CreateFontString(nil, "OVERLAY", "GameFontNormal");
        field.text:SetPoint("TOPLEFT", field, "TOPLEFT", 51, -8);
        field.text:SetWidth(310);
        field.text:SetJustifyH("LEFT");

        field.hint = field:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
        field.hint:SetPoint("BOTTOMLEFT", field, "BOTTOMLEFT", 51, 7);
        field.hint:SetTextColor(0.55, 0.65, 0.75);

        field:SetScript("OnReceiveDrag", function() DMM_ReceiveSpell(fieldIndex); end);
        field:SetScript("OnClick", function()
            if arg1 == "RightButton" then
                DMM_RemoveEditorSpell(fieldIndex);
            end
        end);
        dmmEditorFields[i] = field;
    end

    local resetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    resetLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -300);
    resetLabel:SetText("Zeitreset nach:");

    frame.resetEdit = CreateFrame("EditBox", "DinoMacroManagerSlotResetEdit", frame, "InputBoxTemplate");
    frame.resetEdit:SetWidth(46);
    frame.resetEdit:SetHeight(22);
    frame.resetEdit:SetPoint("LEFT", resetLabel, "RIGHT", 8, 0);
    frame.resetEdit:SetAutoFocus(nil);
    frame.resetEdit:SetMaxLetters(4);

    local resetSecondsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    resetSecondsLabel:SetPoint("LEFT", frame.resetEdit, "RIGHT", 6, 0);
    resetSecondsLabel:SetText("Sekunden (0 = aus)");

    frame.targetResetCheck = CreateFrame("CheckButton", "DinoMacroManagerTargetResetCheck", frame, "UICheckButtonTemplate");
    frame.targetResetCheck:SetWidth(24);
    frame.targetResetCheck:SetHeight(24);
    frame.targetResetCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 25, -326);

    local targetResetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    targetResetLabel:SetPoint("LEFT", frame.targetResetCheck, "RIGHT", 4, 0);
    targetResetLabel:SetText("Bei Targetwechsel auf Zauber 1 resetten");

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.status:SetWidth(374);
    frame.status:SetHeight(16);
    frame.status:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -357);
    frame.status:SetJustifyH("LEFT");

    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    save:SetWidth(80);
    save:SetHeight(24);
    save:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 28, 18);
    save:SetText("Speichern");
    save:SetScript("OnClick", DMM_SaveEditor);

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    clear:SetWidth(72);
    clear:SetHeight(24);
    clear:SetPoint("LEFT", save, "RIGHT", 8, 0);
    clear:SetText("Leeren");
    clear:SetScript("OnClick", DMM_ClearEditorSlot);

    local actionBar = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    actionBar:SetWidth(116);
    actionBar:SetHeight(24);
    actionBar:SetPoint("LEFT", clear, "RIGHT", 8, 0);
    actionBar:SetText("In Leiste ziehen");
    actionBar:RegisterForDrag("LeftButton");
    actionBar:SetScript("OnDragStart", DMM_PickupSlotMacro);
    actionBar:SetScript("OnClick", DMM_PickupSlotMacro);

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    cancel:SetWidth(80);
    cancel:SetHeight(24);
    cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 18);
    cancel:SetText("Abbrechen");
    cancel:SetScript("OnClick", function() frame:Hide(); end);

    dmmEditorFrame = frame;
end

local function DMM_CreateMainFrame()
    local frame = CreateFrame("Frame", "DinoMacroManagerFrame", UIParent);
    frame:SetWidth(546);
    frame:SetHeight(248);
    frame:SetFrameStrata("DIALOG");
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = 1, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    });
    frame:EnableMouse(1);
    frame:SetMovable(1);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", function() this:StartMoving(); end);
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing();
        DMM_SavePosition();
    end);
    frame:Hide();
    dmmMainFrame = frame;

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    title:SetPoint("TOP", frame, "TOP", 0, -16);
    title:SetText("DinoMacroManager");

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5);

    for i = 1, DMM_SLOT_COUNT do
        DMM_CreateSlotButton(i);
    end

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.status:SetWidth(510);
    frame.status:SetHeight(16);
    frame.status:SetPoint("BOTTOM", frame, "BOTTOM", 0, 21);
    frame.status:SetJustifyH("CENTER");

    DMM_RestorePosition();
    DMM_UpdateAllSlots();
end

local function DMM_OnUpdate(elapsed)
    dmmUpdateElapsed = dmmUpdateElapsed + (elapsed or 0);
    if dmmPendingCast then
        local now = GetTime();
        if dmmPendingCast.successAt and now >= dmmPendingCast.successAt then
            DMM_ConfirmPendingCast();
        elseif now - dmmPendingCast.startedAt > DMM_PENDING_TIMEOUT then
            dmmPendingCast = nil;
            DMM_SetStatus("Cast-Bestaetigung abgelaufen; Schritt bleibt unveraendert.", 1);
        end
    end
    if dmmUpdateElapsed < 0.25 then
        return;
    end
    dmmUpdateElapsed = 0;
    local changed = nil;
    if DinoMacroManagerDB then
        for i = 1, DMM_SLOT_COUNT do
            if DMM_ApplyTimeReset(DinoMacroManagerDB.slots[i]) then
                DMM_UpdateSlotButton(i);
                changed = 1;
            end
        end
    end
    if changed then
        DMM_UpdateBlizzardCooldowns();
        DMM_SetStatus("Inaktive Kette auf Schritt 1 zurueckgesetzt.", nil);
    end
end

local function DMM_OnEvent(eventName, firstArg)
    if eventName == "VARIABLES_LOADED" then
        DMM_InitializeDB();
        DMM_CreateEditor();
        DMM_CreateMainFrame();
        return;
    end
    if eventName == "SPELLS_CHANGED" or eventName == "SPELL_UPDATE_COOLDOWN" then
        DMM_UpdateAllSlots();
        return;
    end
    if eventName == "ACTIONBAR_SLOT_CHANGED" or eventName == "ACTIONBAR_PAGE_CHANGED" or eventName == "ACTIONBAR_UPDATE_COOLDOWN" or eventName == "UPDATE_MACROS" or eventName == "UPDATE_BONUS_ACTIONBAR" then
        DMM_UpdateBlizzardCooldowns();
        return;
    end
    if eventName == "PLAYER_TARGET_CHANGED" then
        local changed = nil;
        for i = 1, DMM_SLOT_COUNT do
            local slot = DinoMacroManagerDB.slots[i];
            if slot.resetOnTargetChange then
                if slot.current ~= 1 or slot.lastUsed then
                    slot.current = 1;
                    slot.lastUsed = nil;
                    DMM_UpdateSlotButton(i);
                    changed = 1;
                end
                if dmmPendingCast and dmmPendingCast.slotIndex == i then
                    dmmPendingCast = nil;
                    changed = 1;
                end
            end
        end
        if changed then
            DMM_UpdateBlizzardCooldowns();
            DMM_SetStatus("Targetwechsel: markierte Ketten auf Schritt 1 zurueckgesetzt.", nil);
        end
        return;
    end
    if not dmmPendingCast then
        return;
    end
    if eventName == "SPELLCAST_STOP" or eventName == "SPELLCAST_CHANNEL_STOP" then
        dmmPendingCast.successAt = GetTime() + DMM_SUCCESS_DELAY;
    elseif eventName == "SPELLCAST_FAILED" or eventName == "SPELLCAST_INTERRUPTED" or eventName == "UI_ERROR_MESSAGE" then
        dmmPendingCast = nil;
        DMM_SetStatus("Zauber fehlgeschlagen; Schritt bleibt unveraendert.", 1);
    end
end

function DinoMacroManager_Toggle()
    if not dmmMainFrame then
        return;
    end
    if dmmMainFrame:IsShown() then
        dmmMainFrame:Hide();
        if dmmEditorFrame then
            dmmEditorFrame:Hide();
        end
    else
        DMM_UpdateAllSlots();
        dmmMainFrame:Show();
    end
end

SLASH_DINOMACROMANAGER1 = "/dmm";
SlashCmdList["DINOMACROMANAGER"] = function(msg)
    msg = string.lower(msg or "");
    if msg == "reset" then
        DMM_ResetPosition();
    else
        DinoMacroManager_Toggle();
    end
end;

DMM_InstallPickupSpellHook();

local dmmEventFrame = CreateFrame("Frame", "DinoMacroManagerEventFrame", UIParent);
dmmEventFrame:RegisterEvent("VARIABLES_LOADED");
dmmEventFrame:RegisterEvent("SPELLS_CHANGED");
dmmEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN");
dmmEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED");
dmmEventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED");
dmmEventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN");
dmmEventFrame:RegisterEvent("UPDATE_MACROS");
dmmEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR");
dmmEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED");
dmmEventFrame:RegisterEvent("SPELLCAST_STOP");
dmmEventFrame:RegisterEvent("SPELLCAST_FAILED");
dmmEventFrame:RegisterEvent("SPELLCAST_INTERRUPTED");
dmmEventFrame:RegisterEvent("UI_ERROR_MESSAGE");
dmmEventFrame:RegisterEvent("SPELLCAST_CHANNEL_STOP");
dmmEventFrame:SetScript("OnEvent", function() DMM_OnEvent(event, arg1); end);
dmmEventFrame:SetScript("OnUpdate", function() DMM_OnUpdate(arg1); end);
