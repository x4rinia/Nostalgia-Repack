-- DinoMacroManager 1.1.4 - eigenstaendiges WoW-1.12.1-Addon
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

local DMM = {
    SLOT_COUNT = 14,
    MIN_SPELLS = 2,
    MAX_SPELLS = 4,
    DEFAULT_RESET = 10,
    SUCCESS_DELAY = 0.12,
    PENDING_TIMEOUT = 30,
    BOOKTYPE = BOOKTYPE_SPELL or "spell",
    QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark",

    mainFrame = nil,
    editorFrame = nil,
    slotButtons = {},
    editorFields = {},
    editorSlot = nil,
    editorSpells = {},
    pendingCast = nil,
    updateElapsed = 0,
    pickedSpellIndex = nil,
    pickedSpellBookType = nil,
    pickupHookInstalled = nil,
};

function DMM.InstallPickupSpellHook()
    if DMM.pickupHookInstalled or type(PickupSpell) ~= "function" then
        return;
    end
    local originalPickupSpell = PickupSpell;
    PickupSpell = function(spellIndex, bookType)
        DMM.pickedSpellIndex = spellIndex;
        DMM.pickedSpellBookType = bookType or DMM.BOOKTYPE;
        return originalPickupSpell(spellIndex, bookType);
    end;
    DMM.pickupHookInstalled = 1;
end

function DMM.Chat(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffDinoMacroManager:|r " .. text);
    end
end

function DMM.SetStatus(text, isError)
    if not DMM.mainFrame or not DMM.mainFrame.status then
        return;
    end
    DMM.mainFrame.status:SetText(text or "");
    if isError then
        DMM.mainFrame.status:SetTextColor(1, 0.3, 0.3);
    else
        DMM.mainFrame.status:SetTextColor(0.55, 0.85, 1);
    end
end

function DMM.SetEditorStatus(text, isError)
    if not DMM.editorFrame or not DMM.editorFrame.status then
        return;
    end
    DMM.editorFrame.status:SetText(text or "");
    if isError then
        DMM.editorFrame.status:SetTextColor(1, 0.3, 0.3);
    else
        DMM.editorFrame.status:SetTextColor(0.5, 1, 0.5);
    end
end

function DMM.NewSlot()
    return {
        name = "",
        current = 1,
        spells = {},
        resetSeconds = DMM.DEFAULT_RESET,
        resetOnTargetChange = nil
    };
end

function DMM.InitializeDB()
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
    local oldResetSeconds = tonumber(DinoMacroManagerDB.resetSeconds);
    if not oldResetSeconds or oldResetSeconds < 0 or oldResetSeconds > 3600 then
        oldResetSeconds = DMM.DEFAULT_RESET;
    end
    DinoMacroManagerDB.version = 2;

    for i = 1, DMM.SLOT_COUNT do
        local slot = DinoMacroManagerDB.slots[i];
        if type(slot) ~= "table" then
            slot = DMM.NewSlot();
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
        slot.lastUsed = nil;
        slot.invalid = nil;
    end
    DinoMacroManagerDB.resetSeconds = nil;
end

function DMM.CopySpell(spell)
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

function DMM.SpellMatches(bookIndex, bookType, spell)
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

function DMM.ResolveSpell(spell)
    if type(spell) ~= "table" or type(spell.name) ~= "string" then
        return nil;
    end
    local bookType = spell.bookType or DMM.BOOKTYPE;
    local oldIndex = tonumber(spell.bookIndex);
    if oldIndex and DMM.SpellMatches(oldIndex, bookType, spell) then
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
                if DMM.SpellMatches(index, bookType, spell) then
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

function DMM.ApplyTimeReset(slot)
    if not slot or not slot.lastUsed or slot.current == 1 then
        return nil;
    end
    local resetSeconds = tonumber(slot.resetSeconds) or DMM.DEFAULT_RESET;
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

function DMM.UpdateSlotButton(index)
    local button = DMM.slotButtons[index];
    if not button or not DinoMacroManagerDB then
        return;
    end
    local slot = DinoMacroManagerDB.slots[index];
    DMM.ApplyTimeReset(slot);
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
        button.icon:SetTexture(DMM.QUESTION_ICON);
        button.icon:SetVertexColor(0.45, 0.45, 0.45);
        button.step:SetText("Leer");
        button:SetBackdropBorderColor(0.25, 0.45, 0.65, 0.8);
        slot.invalid = nil;
        if button.cooldown then
            CooldownFrame_SetTimer(button.cooldown, 0, 0, 0);
        end
        DMM.UpdateSlotMacroIcon(index, DMM.QUESTION_ICON);
        return;
    end

    local bookIndex = DMM.ResolveSpell(spell);
    button.icon:SetTexture(spell.icon or DMM.QUESTION_ICON);
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
            local start, duration, enable = GetSpellCooldown(bookIndex, spell.bookType or DMM.BOOKTYPE);
            if start and duration and duration > 0 then
                CooldownFrame_SetTimer(button.cooldown, start, duration, enable);
            else
                CooldownFrame_SetTimer(button.cooldown, 0, 0, 0);
            end
        end
    end
    DMM.UpdateSlotMacroIcon(index, spell.icon or DMM.QUESTION_ICON);
end

function DMM.UpdateAllSlots()
    if not DinoMacroManagerDB then
        return;
    end
    for i = 1, DMM.SLOT_COUNT do
        DMM.UpdateSlotButton(i);
    end
    DMM.UpdateBlizzardCooldowns();
end

function DMM.UpdateEditorFields()
    for i = 1, DMM.MAX_SPELLS do
        local field = DMM.editorFields[i];
        local spell = DMM.editorSpells[i];
        if spell then
            field.icon:SetTexture(spell.icon or DMM.QUESTION_ICON);
            field.icon:SetVertexColor(1, 1, 1);
            local label = spell.name or "Unbekannt";
            if spell.rank and spell.rank ~= "" then
                label = label .. " (" .. spell.rank .. ")";
            end
            field.text:SetText(label);
            field.hint:SetText("Rechtsklick: entfernen");
            field:SetBackdropBorderColor(0.25, 0.65, 0.95, 1);
        else
            field.icon:SetTexture(DMM.QUESTION_ICON);
            field.icon:SetVertexColor(0.35, 0.35, 0.35);
            field.text:SetText("Zauber " .. i .. ": hier ablegen");
            field.hint:SetText("Aus dem normalen Zauberbuch ziehen");
            field:SetBackdropBorderColor(0.3, 0.4, 0.5, 1);
        end
    end
end

function DMM.RemoveEditorSpell(index)
    if not DMM.editorSpells[index] then
        return;
    end
    for i = index, DMM.MAX_SPELLS - 1 do
        DMM.editorSpells[i] = DMM.editorSpells[i + 1];
    end
    DMM.editorSpells[DMM.MAX_SPELLS] = nil;
    DMM.UpdateEditorFields();
    DMM.SetEditorStatus("Zauberplatz entfernt.", nil);
end

function DMM.ReceiveSpell(index)
    local bookIndex, bookType;
    if type(GetCursorInfo) == "function" then
        local cursorType;
        cursorType, bookIndex, bookType = GetCursorInfo();
        if cursorType ~= "spell" then
            DMM.SetEditorStatus("Bitte einen Spielerzauber aus dem Zauberbuch ablegen.", 1);
            return;
        end
    else
        if type(CursorHasSpell) ~= "function" or not CursorHasSpell() then
            DMM.SetEditorStatus("Bitte einen Spielerzauber aus dem Zauberbuch ablegen.", 1);
            return;
        end
        bookIndex = DMM.pickedSpellIndex;
        bookType = DMM.pickedSpellBookType;
        if not bookIndex then
            DMM.SetEditorStatus("Die Spellbook-Referenz konnte nicht gelesen werden.", 1);
            return;
        end
    end
    bookType = bookType or DMM.BOOKTYPE;
    if bookType ~= DMM.BOOKTYPE then
        DMM.SetEditorStatus("Pet-Zauber werden nicht unterstuetzt.", 1);
        return;
    end
    local name, rank = GetSpellName(bookIndex, bookType);
    if not name then
        DMM.SetEditorStatus("Der abgelegte Zauber konnte nicht gelesen werden.", 1);
        return;
    end
    if IsSpellPassive and IsSpellPassive(bookIndex, bookType) then
        DMM.SetEditorStatus("Passive Zauber koennen nicht ausgeloest werden.", 1);
        return;
    end
    DMM.editorSpells[index] = {
        name = name,
        rank = rank or "",
        bookIndex = bookIndex,
        bookType = bookType,
        icon = GetSpellTexture(bookIndex, bookType)
    };
    ClearCursor();
    DMM.pickedSpellIndex = nil;
    DMM.pickedSpellBookType = nil;
    DMM.UpdateEditorFields();
    DMM.SetEditorStatus(name .. " gespeichert (noch nicht uebernommen).", nil);
end

function DMM.OpenEditor(index)
    if not DMM.editorFrame then
        return;
    end
    DMM.editorSlot = index;
    DMM.editorSpells = {};
    local slot = DinoMacroManagerDB.slots[index];
    for i = 1, DMM.MAX_SPELLS do
        DMM.editorSpells[i] = DMM.CopySpell(slot.spells[i]);
    end
    DMM.editorFrame.title:SetText("Slot " .. index .. " bearbeiten");
    DMM.editorFrame.nameEdit:SetText(slot.name or "");
    DMM.editorFrame.resetEdit:SetText(tostring(slot.resetSeconds or DMM.DEFAULT_RESET));
    DMM.editorFrame.targetResetCheck:SetChecked(slot.resetOnTargetChange and 1 or nil);
    DMM.SetEditorStatus("2 bis 4 Zauber aus dem Zauberbuch ablegen.", nil);
    DMM.UpdateEditorFields();
    DMM.editorFrame:Show();
    DMM.editorFrame:Raise();
end

function DMM.SaveEditor()
    if not DMM.editorSlot then
        return;
    end
    local compact = {};
    for i = 1, DMM.MAX_SPELLS do
        if DMM.editorSpells[i] then
            table.insert(compact, DMM.CopySpell(DMM.editorSpells[i]));
        end
    end
    local count = table.getn(compact);
    if count < DMM.MIN_SPELLS or count > DMM.MAX_SPELLS then
        DMM.SetEditorStatus("Eine Kette braucht mindestens 2 und maximal 4 Zauber.", 1);
        return;
    end
    for i = 1, count do
        if not DMM.ResolveSpell(compact[i]) then
            DMM.SetEditorStatus("Zauber " .. i .. " ist nicht mehr im Zauberbuch.", 1);
            return;
        end
    end
    local resetSeconds = tonumber(DMM.editorFrame.resetEdit:GetText());
    if not resetSeconds or resetSeconds < 0 or resetSeconds > 3600 then
        DMM.SetEditorStatus("Resetzeit muss zwischen 0 und 3600 Sekunden liegen.", 1);
        return;
    end
    local slot = DinoMacroManagerDB.slots[DMM.editorSlot];
    slot.name = DMM.editorFrame.nameEdit:GetText() or "";
    slot.spells = compact;
    slot.resetSeconds = resetSeconds;
    slot.resetOnTargetChange = DMM.editorFrame.targetResetCheck:GetChecked() and 1 or nil;
    slot.current = 1;
    slot.lastUsed = nil;
    slot.invalid = nil;
    DMM.UpdateAllSlots();
    DMM.SetStatus("Slot " .. DMM.editorSlot .. " gespeichert.", nil);
    DMM.editorFrame:Hide();
end

function DMM.ClearEditorSlot()
    if not DMM.editorSlot then
        return;
    end
    DinoMacroManagerDB.slots[DMM.editorSlot] = DMM.NewSlot();
    DMM.editorSpells = {};
    DMM.editorFrame.nameEdit:SetText("");
    DMM.editorFrame.resetEdit:SetText(tostring(DMM.DEFAULT_RESET));
    DMM.editorFrame.targetResetCheck:SetChecked(nil);
    DMM.UpdateEditorFields();
    DMM.UpdateAllSlots();
    DMM.SetEditorStatus("Der komplette Slot wurde geleert.", nil);
    DMM.SetStatus("Slot " .. DMM.editorSlot .. " geleert.", nil);
end

function DMM.FindSlotMacro(index)
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

function DMM.FindMacroIconIndex(texture)
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

function DMM.UpdateSlotMacroIcon(index, icon)
    if type(EditMacro) ~= "function" then
        return;
    end
    local macroIndex, macroName, macroIcon, macroBody = DMM.FindSlotMacro(index);
    if macroIndex and icon and macroIcon ~= icon then
        EditMacro(macroIndex, macroName, DMM.FindMacroIconIndex(icon), macroBody, 1, 1);
    end
end

function DMM.EditorHasUnsavedChanges()
    if not DMM.editorSlot or not DinoMacroManagerDB then
        return false;
    end
    local slot = DinoMacroManagerDB.slots[DMM.editorSlot];
    if not slot then
        return true;
    end

    local currentName = (DMM.editorFrame and DMM.editorFrame.nameEdit and DMM.editorFrame.nameEdit:GetText()) or "";
    if currentName ~= (slot.name or "") then
        return true;
    end

    local currentReset = (DMM.editorFrame and DMM.editorFrame.resetEdit and tonumber(DMM.editorFrame.resetEdit:GetText())) or DMM.DEFAULT_RESET;
    local savedReset = tonumber(slot.resetSeconds) or DMM.DEFAULT_RESET;
    if currentReset ~= savedReset then
        return true;
    end

    local currentTargetReset = (DMM.editorFrame and DMM.editorFrame.targetResetCheck and DMM.editorFrame.targetResetCheck:GetChecked()) and 1 or nil;
    local savedTargetReset = slot.resetOnTargetChange and 1 or nil;
    if currentTargetReset ~= savedTargetReset then
        return true;
    end

    local editorCount = 0;
    for i = 1, DMM.MAX_SPELLS do
        if DMM.editorSpells[i] then
            editorCount = editorCount + 1;
        end
    end
    local savedCount = (slot.spells and table.getn(slot.spells)) or 0;
    if editorCount ~= savedCount then
        return true;
    end

    for i = 1, editorCount do
        local eSpell = DMM.editorSpells[i];
        local sSpell = slot.spells[i];
        if not eSpell or not sSpell then
            return true;
        end
        if eSpell.name ~= sSpell.name or (eSpell.rank or "") ~= (sSpell.rank or "") then
            return true;
        end
    end

    if savedCount < DMM.MIN_SPELLS then
        return true;
    end

    return false;
end

-- =========================================================================
-- Oeffentliche API-Funktionen fuer Integrationen (DinoControllerHUD etc.)
-- =========================================================================

function DinoMacroManager_GetSlotFromAction(actionSlot)
    if not actionSlot or type(GetActionText) ~= "function" then return nil; end
    local text = GetActionText(actionSlot);
    if not text then return nil; end
    local _, _, num = string.find(text, "^DMM Slot (%d+)$");
    if num then
        return tonumber(num);
    end
    return nil;
end

function DinoMacroManager_GetSlotCurrentSpell(slotIndex)
    if not slotIndex or not DinoMacroManagerDB or not DinoMacroManagerDB.slots then return nil; end
    local slot = DinoMacroManagerDB.slots[slotIndex];
    if not slot or not slot.spells then return nil; end
    DMM.ApplyTimeReset(slot);
    local cur = slot.current or 1;
    local spell = slot.spells[cur];
    if not spell then return nil; end
    local bookIndex = DMM.ResolveSpell(spell);
    return spell, bookIndex, cur, table.getn(slot.spells);
end

function DMM.GetSpellResourceCost(bookIndex, bookType)
    if not DMM.scannerTooltip then
        DMM.scannerTooltip = CreateFrame("GameTooltip", "DMMScanTooltip", UIParent, "GameTooltipTemplate");
        DMM.scannerTooltip:SetOwner(UIParent, "ANCHOR_NONE");
    end
    DMM.scannerTooltip:ClearLines();
    DMM.scannerTooltip:SetSpell(bookIndex, bookType or DMM.BOOKTYPE);
    for lineIndex = 2, 4 do
        local line = getglobal("DMMScanTooltipTextLeft" .. lineIndex);
        local text = line and line:GetText();
        if text then
            local _, _, costStr = string.find(text, "^(%d+)%s+[Mm]ana");
            if costStr then return tonumber(costStr), "MANA"; end
            _, _, costStr = string.find(text, "^(%d+)%s+[Ee]nergie");
            if costStr then return tonumber(costStr), "ENERGY"; end
            _, _, costStr = string.find(text, "^(%d+)%s+[Ee]nergy");
            if costStr then return tonumber(costStr), "ENERGY"; end
            _, _, costStr = string.find(text, "^(%d+)%s+[Ww]ut");
            if costStr then return tonumber(costStr), "RAGE"; end
            _, _, costStr = string.find(text, "^(%d+)%s+[Rr]age");
            if costStr then return tonumber(costStr), "RAGE"; end
            _, _, costStr = string.find(text, "^(%d+)%s+[Ff]okus");
            if costStr then return tonumber(costStr), "FOCUS"; end
            _, _, costStr = string.find(text, "^(%d+)%s+[Ff]ocus");
            if costStr then return tonumber(costStr), "FOCUS"; end
        end
    end
    return nil, nil;
end

function DinoMacroManager_GetSlotCooldown(slotIndex)
    local spell, bookIndex = DinoMacroManager_GetSlotCurrentSpell(slotIndex);
    if not spell or not bookIndex then return 0, 0, 0; end
    local start, duration, enable = GetSpellCooldown(bookIndex, spell.bookType or DMM.BOOKTYPE);
    return start or 0, duration or 0, enable or 0;
end

function DinoMacroManager_IsSlotUsable(slotIndex)
    local spell, bookIndex = DinoMacroManager_GetSlotCurrentSpell(slotIndex);
    if not spell or not bookIndex then return false, false; end

    for actSlot = 1, 120 do
        if HasAction(actSlot) and not GetActionText(actSlot) then
            local texture = GetActionTexture(actSlot);
            if texture and spell.icon and texture == spell.icon then
                local isUsable, notEnoughMana = IsUsableAction(actSlot);
                if isUsable ~= nil then
                    return isUsable, notEnoughMana;
                end
            end
        end
    end

    if type(IsUsableSpell) == "function" then
        local ok, isUsable, notEnoughMana = pcall(IsUsableSpell, bookIndex, spell.bookType or DMM.BOOKTYPE);
        if ok and isUsable ~= nil then
            return isUsable, notEnoughMana;
        end
    end

    local cost, powerType = DMM.GetSpellResourceCost(bookIndex, spell.bookType or DMM.BOOKTYPE);
    if cost and cost > 0 then
        local currentPower = UnitMana("player") or 0;
        if currentPower < cost then
            return false, true;
        end
    end

    local start, duration, enable = GetSpellCooldown(bookIndex, spell.bookType or DMM.BOOKTYPE);
    if enable == 0 or (start and duration and duration > 0 and start + duration > GetTime()) then
        return false, false;
    end
    return true, false;
end

function DinoMacroManager_IsSlotInRange(slotIndex, unit)
    local spell, bookIndex = DinoMacroManager_GetSlotCurrentSpell(slotIndex);
    if not spell or not bookIndex then return nil; end
    unit = unit or "target";
    if not UnitExists(unit) or UnitIsDead(unit) then return nil; end

    if type(IsSpellInRange) == "function" then
        local ok, res = pcall(IsSpellInRange, bookIndex, spell.bookType or DMM.BOOKTYPE, unit);
        if ok and res ~= nil then return res; end
        local ok2, res2 = pcall(IsSpellInRange, spell.name, unit);
        if ok2 and res2 ~= nil then return res2; end
    end

    if type(SpellHasRange) == "function" and SpellHasRange(bookIndex, spell.bookType or DMM.BOOKTYPE) ~= 1 then
        return nil;
    end

    for actSlot = 1, 120 do
        if HasAction(actSlot) and not GetActionText(actSlot) then
            local texture = GetActionTexture(actSlot);
            if texture and spell.icon and texture == spell.icon then
                local inRange = IsActionInRange(actSlot);
                if inRange ~= nil then
                    return inRange;
                end
            end
        end
    end

    return nil;
end

function DMM.PickupSlotMacro()
    if not DMM.editorSlot then
        return;
    end

    if DMM.EditorHasUnsavedChanges() then
        DMM.SetEditorStatus("Bitte die Kette zuerst mit 'Speichern' sichern!", 1);
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("Bitte die Kette zuerst mit 'Speichern' sichern!", 1.0, 0.2, 0.2, 1.0);
        else
            DMM.Chat("Bitte die Kette zuerst mit 'Speichern' sichern, bevor sie in die Leiste gezogen wird.");
        end
        return;
    end

    local index = DMM.editorSlot;
    local slot = DinoMacroManagerDB.slots[index];
    local count = (slot and slot.spells and table.getn(slot.spells)) or 0;
    if count < DMM.MIN_SPELLS then
        DMM.SetEditorStatus("Eine Kette braucht mindestens " .. DMM.MIN_SPELLS .. " Zauber.", 1);
        return;
    end

    if type(CreateMacro) ~= "function" or type(PickupMacro) ~= "function" then
        DMM.SetEditorStatus("Dieser Client stellt die Makro-APIs nicht bereit.", 1);
        return;
    end

    local spell = slot.spells[slot.current or 1];
    local icon = (spell and spell.icon) or DMM.QUESTION_ICON;
    local macroIndex = DMM.FindSlotMacro(index);
    if not macroIndex then
        local macroName = "DMM Slot " .. index;
        local macroBody = "/script DinoMacroManager_ExecuteSlot(" .. index .. ")";
        macroIndex = CreateMacro(macroName, DMM.FindMacroIconIndex(icon), macroBody, 1, 1);
        macroIndex = DMM.FindSlotMacro(index) or macroIndex;
    end
    if not macroIndex or macroIndex == 0 then
        DMM.SetEditorStatus("Kein freier charakterspezifischer Makroplatz.", 1);
        return;
    end
    ClearCursor();
    PickupMacro(macroIndex);
    DMM.SetEditorStatus("DMM Slot " .. index .. " liegt am Cursor: jetzt auf die Leiste ziehen.", nil);
end

function DMM.UpdateBlizzardButtonCooldown(button)
    if not button or type(ActionButton_GetPagedID) ~= "function" then
        return;
    end
    local actionSlot = ActionButton_GetPagedID(button);
    local slotIndex = DinoMacroManager_GetSlotFromAction(actionSlot);
    local overlay = button.dmmMacroCooldown;

    if not slotIndex then
        if overlay then
            CooldownFrame_SetTimer(overlay, 0, 0, 0);
            overlay:Hide();
        end
        return;
    end

    local btnName = button:GetName();
    if not overlay then
        overlay = CreateFrame("Model", btnName .. "DMMCooldown", button, "CooldownFrameTemplate");
        overlay:SetWidth(36);
        overlay:SetHeight(36);
        overlay:SetPoint("CENTER", button, "CENTER", 0, 0);
        overlay:SetFrameLevel(button:GetFrameLevel() + 2);
        button.dmmMacroCooldown = overlay;
    end

    local start, duration, enable = DinoMacroManager_GetSlotCooldown(slotIndex);
    if start and duration and duration > 0 then
        CooldownFrame_SetTimer(overlay, start, duration, enable);
        overlay:Show();
    else
        CooldownFrame_SetTimer(overlay, 0, 0, 0);
        overlay:Hide();
    end

    local icon = getglobal(btnName .. "Icon");
    local spell, bookIndex = DinoMacroManager_GetSlotCurrentSpell(slotIndex);
    if spell and spell.icon and icon then
        icon:SetTexture(spell.icon);
    end

    local isUsable, notEnoughMana = DinoMacroManager_IsSlotUsable(slotIndex);
    local inRange = DinoMacroManager_IsSlotInRange(slotIndex, "target");

    if icon then
        if inRange == 0 then
            icon:SetVertexColor(0.8, 0.1, 0.1);
        elseif not isUsable then
            if notEnoughMana then
                icon:SetVertexColor(0.3, 0.3, 0.8);
            else
                icon:SetVertexColor(0.4, 0.4, 0.4);
            end
        else
            icon:SetVertexColor(1.0, 1.0, 1.0);
        end
    end
end

function DMM.UpdateBlizzardCooldowns()
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
            DMM.UpdateBlizzardButtonCooldown(getglobal(prefixes[prefixIndex] .. buttonIndex));
        end
    end
end

function DMM.ConfirmPendingCast()
    local pending = DMM.pendingCast;
    if not pending then
        return;
    end
    local slot = DinoMacroManagerDB.slots[pending.slotIndex];
    if not slot or slot.current ~= pending.step or slot.spells[pending.step] ~= pending.spell then
        DMM.pendingCast = nil;
        return;
    end
    local count = table.getn(slot.spells);
    slot.current = slot.current + 1;
    if slot.current > count then
        slot.current = 1;
    end
    slot.lastUsed = GetTime();
    DMM.pendingCast = nil;
    DMM.UpdateSlotButton(pending.slotIndex);
    DMM.UpdateBlizzardCooldowns();
    DMM.SetStatus("Slot " .. pending.slotIndex .. ": naechster Schritt " .. slot.current .. ".", nil);
end

function DinoMacroManager_TriggerSlot(index)
    index = tonumber(index);
    if not index or index < 1 or index > DMM.SLOT_COUNT or not DinoMacroManagerDB then
        return;
    end
    local slot = DinoMacroManagerDB.slots[index];
    DMM.ApplyTimeReset(slot);
    local count = table.getn(slot.spells);
    if count < DMM.MIN_SPELLS or count > DMM.MAX_SPELLS then
        DMM.SetStatus("Slot " .. index .. " ist leer oder unvollstaendig.", 1);
        DMM.OpenEditor(index);
        return;
    end
    if DMM.pendingCast then
        DMM.SetStatus("Ein Zauber wartet noch auf seine Cast-Bestaetigung.", 1);
        return;
    end
    if slot.current < 1 or slot.current > count then
        slot.current = 1;
    end
    local spell = slot.spells[slot.current];
    local bookIndex = DMM.ResolveSpell(spell);
    if not bookIndex then
        slot.invalid = 1;
        DMM.UpdateSlotButton(index);
        DMM.SetStatus("Slot " .. index .. ": aktueller Zauber ist ungueltig.", 1);
        return;
    end

    local start, duration, enabled = GetSpellCooldown(bookIndex, spell.bookType or DMM.BOOKTYPE);
    if enabled == 0 or (start and duration and duration > 0 and start + duration > GetTime()) then
        DMM.SetStatus("Slot " .. index .. ": aktueller Zauber ist noch nicht bereit.", 1);
        return;
    end

    local castName = spell.name;
    if spell.rank and spell.rank ~= "" then
        castName = castName .. "(" .. spell.rank .. ")";
    end
    DMM.pendingCast = {
        slotIndex = index,
        step = slot.current,
        spell = spell,
        startedAt = GetTime(),
        successAt = nil
    };
    CastSpellByName(castName);
end

function DinoMacroManager_ExecuteSlot(slot)
    DinoMacroManager_TriggerSlot(slot);
end

function DMM.SavePosition()
    if not DMM.mainFrame or not DinoMacroManagerDB then
        return;
    end
    local point, relativeTo, relativePoint, x, y = DMM.mainFrame:GetPoint();
    DinoMacroManagerDB.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0
    };
end

function DMM.RestorePosition()
    local pos = DinoMacroManagerDB.position;
    DMM.mainFrame:ClearAllPoints();
    DMM.mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0);
end

function DMM.ResetPosition()
    DinoMacroManagerDB.position = {
        point = "CENTER", relativePoint = "CENTER", x = 0, y = 0
    };
    DMM.RestorePosition();
    DMM.SetStatus("Fensterposition zurueckgesetzt.", nil);
end

function DMM.CreateSlotButton(index)
    local button = CreateFrame("Button", "DinoMacroManagerSlot" .. index, DMM.mainFrame);
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
    button:SetPoint("TOPLEFT", DMM.mainFrame, "TOPLEFT", 14 + col * 74, -40 - row * 84);

    button.number = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    button.number:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -5);
    button.number:SetText(tostring(index));

    button.icon = button:CreateTexture(nil, "ARTWORK");
    button.icon:SetWidth(38);
    button.icon:SetHeight(38);
    button.icon:SetPoint("TOP", button, "TOP", 0, -18);
    button.icon:SetTexture(DMM.QUESTION_ICON);

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
            DMM.OpenEditor(index);
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
    DMM.slotButtons[index] = button;
end

function DMM.CreateEditor()
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

    for i = 1, DMM.MAX_SPELLS do
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

        field:SetScript("OnReceiveDrag", function() DMM.ReceiveSpell(fieldIndex); end);
        field:SetScript("OnClick", function()
            if arg1 == "RightButton" then
                DMM.RemoveEditorSpell(fieldIndex);
            end
        end);
        DMM.editorFields[i] = field;
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
    save:SetScript("OnClick", DMM.SaveEditor);

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    clear:SetWidth(72);
    clear:SetHeight(24);
    clear:SetPoint("LEFT", save, "RIGHT", 8, 0);
    clear:SetText("Leeren");
    clear:SetScript("OnClick", DMM.ClearEditorSlot);

    local actionBar = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    actionBar:SetWidth(116);
    actionBar:SetHeight(24);
    actionBar:SetPoint("LEFT", clear, "RIGHT", 8, 0);
    actionBar:SetText("In Leiste ziehen");
    actionBar:RegisterForDrag("LeftButton");
    actionBar:SetScript("OnDragStart", DMM.PickupSlotMacro);
    actionBar:SetScript("OnClick", DMM.PickupSlotMacro);

    local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    cancel:SetWidth(80);
    cancel:SetHeight(24);
    cancel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 18);
    cancel:SetText("Abbrechen");
    cancel:SetScript("OnClick", function() frame:Hide(); end);

    DMM.editorFrame = frame;
end

function DMM.CreateMainFrame()
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
        DMM.SavePosition();
    end);
    frame:Hide();
    DMM.mainFrame = frame;

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    title:SetPoint("TOP", frame, "TOP", 0, -16);
    title:SetText("DinoMacroManager");

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5);

    for i = 1, DMM.SLOT_COUNT do
        DMM.CreateSlotButton(i);
    end

    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.status:SetWidth(510);
    frame.status:SetHeight(16);
    frame.status:SetPoint("BOTTOM", frame, "BOTTOM", 0, 21);
    frame.status:SetJustifyH("CENTER");

    DMM.RestorePosition();
    DMM.UpdateAllSlots();
end

function DMM.OnUpdate(elapsed)
    DMM.updateElapsed = DMM.updateElapsed + (elapsed or 0);
    if DMM.pendingCast then
        local now = GetTime();
        if DMM.pendingCast.successAt and now >= DMM.pendingCast.successAt then
            DMM.ConfirmPendingCast();
        elseif now - DMM.pendingCast.startedAt > DMM.PENDING_TIMEOUT then
            DMM.pendingCast = nil;
            DMM.SetStatus("Cast-Bestaetigung abgelaufen; Schritt bleibt unveraendert.", 1);
        end
    end
    if DMM.updateElapsed < 0.08 then
        return;
    end
    DMM.updateElapsed = 0;
    local changed = nil;
    if DinoMacroManagerDB then
        for i = 1, DMM.SLOT_COUNT do
            if DMM.ApplyTimeReset(DinoMacroManagerDB.slots[i]) then
                DMM.UpdateSlotButton(i);
                changed = 1;
            end
        end
    end
    if changed then
        DMM.SetStatus("Inaktive Kette auf Schritt 1 zurueckgesetzt.", nil);
    end
    DMM.UpdateBlizzardCooldowns();
end

function DMM.OnEvent(eventName, firstArg)
    if eventName == "VARIABLES_LOADED" then
        DMM.InitializeDB();
        DMM.CreateEditor();
        DMM.CreateMainFrame();
        return;
    end
    if eventName == "SPELLS_CHANGED" or eventName == "SPELL_UPDATE_COOLDOWN" then
        DMM.UpdateAllSlots();
        return;
    end
    if eventName == "ACTIONBAR_SLOT_CHANGED" or eventName == "ACTIONBAR_PAGE_CHANGED" or eventName == "ACTIONBAR_UPDATE_COOLDOWN" or eventName == "UPDATE_MACROS" or eventName == "UPDATE_BONUS_ACTIONBAR" then
        DMM.UpdateBlizzardCooldowns();
        return;
    end
    if eventName == "PLAYER_TARGET_CHANGED" then
        local changed = nil;
        for i = 1, DMM.SLOT_COUNT do
            local slot = DinoMacroManagerDB.slots[i];
            if slot.resetOnTargetChange then
                if slot.current ~= 1 or slot.lastUsed then
                    slot.current = 1;
                    slot.lastUsed = nil;
                    DMM.UpdateSlotButton(i);
                    changed = 1;
                end
                if DMM.pendingCast and DMM.pendingCast.slotIndex == i then
                    DMM.pendingCast = nil;
                    changed = 1;
                end
            end
        end
        if changed then
            DMM.UpdateBlizzardCooldowns();
            DMM.SetStatus("Targetwechsel: markierte Ketten auf Schritt 1 zurueckgesetzt.", nil);
        end
        return;
    end
    if not DMM.pendingCast then
        return;
    end
    if eventName == "SPELLCAST_STOP" or eventName == "SPELLCAST_CHANNEL_STOP" then
        DMM.pendingCast.successAt = GetTime() + DMM.SUCCESS_DELAY;
    elseif eventName == "SPELLCAST_FAILED" or eventName == "SPELLCAST_INTERRUPTED" or eventName == "UI_ERROR_MESSAGE" then
        DMM.pendingCast = nil;
        DMM.SetStatus("Zauber fehlgeschlagen; Schritt bleibt unveraendert.", 1);
    end
end

function DinoMacroManager_Toggle()
    if not DMM.mainFrame then
        return;
    end
    if DMM.mainFrame:IsShown() then
        DMM.mainFrame:Hide();
        if DMM.editorFrame then
            DMM.editorFrame:Hide();
        end
    else
        DMM.UpdateAllSlots();
        DMM.mainFrame:Show();
    end
end

SLASH_DINOMACROMANAGER1 = "/dmm";
SlashCmdList["DINOMACROMANAGER"] = function(msg)
    msg = string.lower(msg or "");
    if msg == "reset" then
        DMM.ResetPosition();
    else
        DinoMacroManager_Toggle();
    end
end;

DMM.InstallPickupSpellHook();

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
dmmEventFrame:SetScript("OnEvent", function() DMM.OnEvent(event, arg1); end);
dmmEventFrame:SetScript("OnUpdate", function() DMM.OnUpdate(arg1); end);
