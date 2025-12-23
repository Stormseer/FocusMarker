local ADDON_NAME = "FocusMarker"
local SAVEDVARS = "AryFocusMarkerDB"
local MACRO_NAME = "FocusMarker"
local MACRO_CONDITIONALS_DEFAULT = "[@mouseover,exists,nodead][]"
local MACRO_ICON = 1033497
local settingsCategory


-- default
local globalDefaults = {
    selectedMarker = "Star"
}

-- alias mapping
local colorAliases = {
    yellow      = "Star",
    y           = "Star",
    star        = "Star",
    orange      = "Circle",
    o           = "Circle",
    circle      = "Circle",
    purple      = "Diamond",
    p           = "Diamond",
    diamond     = "Diamond",
    bruno       = "Diamond",
    green       = "Triangle",
    g           = "Triangle",
    triangle    = "Triangle",
    m           = "Moon",
    moon        = "Moon",
    blue        = "Square",
    b           = "Square",
    square      = "Square",
    red         = "Cross",
    r           = "Cross",
    x           = "Cross",
    cross       = "Cross",
    white       = "Skull",
    w           = "Skull",
    skull       = "Skull",
    none        = "None",
    off         = "None",
    default     = "Star",
}

-- Helpers to translate marker names to index and vise versa.
local optionsOrder = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull", "None" }
local nameToIndex = {
    Star = 1,
    Circle = 2,
    Diamond = 3,
    Triangle = 4,
    Moon = 5,
    Square = 6,
    Cross = 7,
    Skull = 8,
    None = 0,
}

-- Icon paths to each marker, for the options menu.
local markerTextures = {
    Star     = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:16|t",
    Circle   = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:16|t",
    Diamond  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:16|t",
    Triangle = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:16|t",
    Moon     = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:16|t",
    Square   = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:16|t",
    Cross    = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:16|t",
    Skull    = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16|t",
    None     = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:16|t", -- A small red circle with a line through.
}


-- saved variables table
local db

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName ~= ADDON_NAME then return end

    if not AryFocusMarkerDB then
        AryFocusMarkerDB = {}
    end

    db = AryFocusMarkerDB
    if not db.selectedMarker then
        db.selectedMarker = globalDefaults.selectedMarker
    end
end)


-- Pending macro update state (used when macro APIs are protected during combat)
local pendingMacroName = nil
local pendingMacroIcon = nil
local pendingMacroBody = nil
local pendingMacroQueued = false
local pendingMacroOldName = nil

-- Try to create or edit macro now; returns true on success, false and err on failure.
local function ApplyMacroNow(name, icon, body, oldName)
    if InCombatLockdown() then
        return false, "incombat"
    end

    local ok, err = pcall(function()
        -- 1) If a macro with the new name already exists, just edit it
        local mIndex = GetMacroIndexByName(name)
        if mIndex and mIndex > 0 then
            EditMacro(mIndex, name, icon, body)
            return
        end

        -- 2) Otherwise, if we know an old name, try to rename that macro
        if oldName and oldName ~= name then
            local oldIndex = GetMacroIndexByName(oldName)
            if oldIndex and oldIndex > 0 then
                -- Rename + update body/icon in one go
                EditMacro(oldIndex, name, icon, body)
                return
            end
        end

        -- 3) No existing macro under either name -> create a new one
        CreateMacro(name, icon, body, nil) -- global macro
    end)

    if not ok then
        return false, err
    end

    return true
end

-- Helper function to get conditionals for the macro.
local function GetMacroConditionals()
    if db and db.macroConditionals and db.macroConditionals ~= "" then
        return db.macroConditionals
    end
    return MACRO_CONDITIONALS_DEFAULT
end


-- Frame to handle queued regen events
local queuedFrame = CreateFrame("Frame", ADDON_NAME .. "QueuedFrame")
queuedFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingMacroQueued and not InCombatLockdown() then
            local ok, err = ApplyMacroNow(
                pendingMacroName,
                pendingMacroIcon,
                pendingMacroBody,
                pendingMacroOldName
            )
            if ok then
                pendingMacroQueued = false
                pendingMacroName = nil
                pendingMacroIcon = nil
                pendingMacroBody = nil
                pendingMacroOldName = nil
                queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                print("|cffffff00["..ADDON_NAME.."]|r Macro '"..(db.macroName or MACRO_NAME).."' updated after combat.")
            else
                print("|cffffff00["..ADDON_NAME.."]|r Failed to update macro after combat: "..tostring(err))
                pendingMacroQueued = false
                pendingMacroName = nil
                pendingMacroIcon = nil
                pendingMacroBody = nil
                pendingMacroOldName = nil
                queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
    end
end)

-- Build the macro body given an index (0..8)
local function BuildMacroBodyForIndex(idx)
    local lines = {}
    local cond = GetMacroConditionals() or MACRO_CONDITIONALS_DEFAULT

    -- Only add the /focus line if we are NOT in mark-only mode
    if not (db and db.markOnly) then
        table.insert(lines, "/focus " .. cond)
    end

    -- Add raid conditional only if the option is enabled
    local tmCond = cond
    if db and db.noRaid then
        -- Strip outer brackets and inject nogroup:raid
        local inner = cond:match("^%[(.*)%]$") or cond
        tmCond = "[nogroup:raid," .. inner .. "]"
    end

    -- Always add the targeting marker line
    table.insert(lines, "/tm " .. tmCond .. " " .. tostring(idx))

    return table.concat(lines, "\n")
end


-- Helper function that gets the currently set icon.
local function GetCurrentMacroIcon()
    if db and db.macroIconId then
        return db.macroIconId
    end
    return MACRO_ICON
end

-- Queue a macro update to run after combat ends
local function QueueMacroUpdate(name, icon, body, oldName)
    pendingMacroName = name
    pendingMacroIcon = icon
    pendingMacroBody = body
    pendingMacroOldName = oldName
    pendingMacroQueued = true
    queuedFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    print("|cffffff00["..ADDON_NAME.."]|r In combat: will update macro after combat.")
end

-- Attempt to apply pending macro (safe-guard; used from event handlers)
local function TryApplyPendingMacro()
    if not pendingMacroQueued then return end
    if InCombatLockdown() then return end

    local ok, err = ApplyMacroNow(
        pendingMacroName,
        pendingMacroIcon,
        pendingMacroBody,
        pendingMacroOldName
    )
    if ok then
        pendingMacroQueued = false
        pendingMacroName = nil
        pendingMacroIcon = nil
        pendingMacroBody = nil
        pendingMacroOldName = nil  
        queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        print("|cffffff00["..ADDON_NAME.."]|r Macro updated after combat.")
    else
        if err ~= "incombat" then
            print("|cffffff00["..ADDON_NAME.."]|r Failed to update macro: "..tostring(err))
            pendingMacroQueued = false
            pendingMacroName = nil
            pendingMacroIcon = nil
            pendingMacroBody = nil
            pendingMacroOldName = nil 
            queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end
end


-- Core event frame: listens for READY_CHECK and PLAYER_REGEN_ENABLED (regen handled on queuedFrame)
local frame = CreateFrame("Frame", ADDON_NAME .. "Frame")
frame:RegisterEvent("READY_CHECK")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "READY_CHECK" then
        -- Only post to party if user has it configured to.
        if db and db.announceReadyCheck == false then
            return
        end

        -- Announce to party chat only when in a party (not raid) and not in combat
        if IsInGroup() and not IsInRaid() and not InCombatLockdown() then
            local markerName = db.selectedMarker or globalDefaults.selectedMarker
            local msg = ("My Focus Marker is {%s}"):format(markerName)
            -- Send to party chat
            C_ChatInfo.SendChatMessage(msg, "PARTY")

        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- allow queuedFrame logic to apply pending macros; also call TryApplyPendingMacro
        TryApplyPendingMacro()
    end
end)

-- Helper: set selected marker (by canonical name) and apply macro immediately
local function SetSelectedMarkerByName(name)
    if not name then return end
    -- normalize to string
    local canonical = tostring(name)
    -- if passed a number string like "1" convert to the canonical name
    local n = tonumber(canonical)
    if n then
        for k,v in pairs(nameToIndex) do
            if v == n then canonical = k; break end
        end
    end
    -- alias resolution
    local low = strlower(canonical)
    if colorAliases[low] then canonical = colorAliases[low] end

    -- validate
    local valid = false
    for _,v in ipairs(optionsOrder) do
        if v == canonical then valid = true; break end
    end
    if not valid then
        print("|cffffff00["..ADDON_NAME.."]|r Unknown marker '"..tostring(name).."'. Valid commands are: Star, Circle, Diamond, Triangle, Moon, Square, Cross, Skull, None.")
        return
    end

    -- Only proceed if the marker actually changed
    if db.selectedMarker == canonical then
        print("|cffffff00["..ADDON_NAME.."]|r Marker already set to: "..canonical)
        return
    end

    db.selectedMarker = canonical
    print("|cffffff00["..ADDON_NAME.."]|r Selected marker set to: "..canonical)

    -- update macro immediately (or queue if combat)
    local idx = nameToIndex[canonical] or 0
    local body = BuildMacroBodyForIndex(idx)
    local ok, err = ApplyMacroNow(db.macroName or MACRO_NAME, GetCurrentMacroIcon(), body)
    if not ok then
        if err == "incombat" then
            QueueMacroUpdate(db.macroName or MACRO_NAME, GetCurrentMacroIcon(), body)
        else
            print("|cffffff00["..ADDON_NAME.."]|r Failed to create/update macro '"..(db.macroName or MACRO_NAME).."': "..tostring(err))
        end
    end

    -- update dropdown value if present
    if FocusMarkerOptions and FocusMarkerOptions.dropdown and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(FocusMarkerOptions.dropdown, canonical)
    end
end

-----------------------------------------------------------------------
-- Slash Command
-----------------------------------------------------------------------
SLASH_FOCUSMARKER1 = "/focusmarker"
SLASH_FOCUSMARKER2 = "/fm"
SlashCmdList["FOCUSMARKER"] = function(msg)
    msg = msg and strtrim(msg) or ""
    if msg == "" then
        print("|cffffff00["..ADDON_NAME.."]|r Current marker: "..(db.selectedMarker or globalDefaults.selectedMarker))
        print("|cffffff00["..ADDON_NAME.."]|r Usage: /focusmarker <name/number>  (e.g. /focusmarker star  or /focusmarker 1)")
        print("|cffffff00["..ADDON_NAME.."]|r Open Addon Menu for more options.")
        return
    end

    if msg == "option" or msg == "options" or msg == "menu" then
        if Settings and Settings.OpenToCategory then
            if settingsCategory and settingsCategory.GetID then
                Settings.OpenToCategory(settingsCategory:GetID())
            else
                Settings.OpenToCategory(ADDON_NAME)
            end
        else
            print("|cffffff00["..ADDON_NAME.."]|r Unable to open options menu. Try manually?")
        end
    else 
        -- take first token
        local first = strsplit(" ", msg)
        SetSelectedMarkerByName(first)
    end
    
end

-----------------------------------------------------------------------
-- 💀💀💀💀
-- It's all Options Panel from down here (enter at your own risk)
-----------------------------------------------------------------------
do
    local panel = CreateFrame("Frame", "FocusMarkerOptionsPanel")
    panel.name = "FocusMarker"
    panel:Hide()

    -- Shared table for references from elsewhere (e.g. SetSelectedMarkerByName)
    FocusMarkerOptions = FocusMarkerOptions or {}

    panel:SetScript("OnShow", function(self)
        if self.initialized then return end
        self.initialized = true

        -- Safety: ensure db exists (in case of weird load order)
        db = db or _G[SAVEDVARS] or {}
        if not db.selectedMarker then
            db.selectedMarker = globalDefaults.selectedMarker
        end
        if not db.macroName then
            db.macroName = MACRO_NAME
        end


        ----------------------------------------------------------------
        -- Title & description
        ----------------------------------------------------------------
        local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Focus Marker")

        local desc = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        desc:SetJustifyH("LEFT")
        desc:SetText("Made by Aryella on Silvermoon EU")

        ----------------------------------------------------------------
        -- Marker dropdown
        ----------------------------------------------------------------
        local markerLabel = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        markerLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -22)
        markerLabel:SetText("Selected marker:")

        local dropdown = CreateFrame("Frame", "FocusMarkerOptionsMarkerDropdown", self, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", markerLabel, "BOTTOMLEFT", -20, -3)

        -- Expose to the rest of the addon (used in SetSelectedMarkerByName)
        FocusMarkerOptions.dropdown = dropdown

        local function MarkerDropdown_OnClick(button)
            local value = button.value
            if UIDropDownMenu_SetSelectedValue then
                UIDropDownMenu_SetSelectedValue(dropdown, value)
            end
            if SetSelectedMarkerByName then
                SetSelectedMarkerByName(value)
            else
                db.selectedMarker = value
            end
        end

        if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo then
            UIDropDownMenu_Initialize(dropdown, function(frame, level, menuList)
                local info = UIDropDownMenu_CreateInfo()
                for _, name in ipairs(optionsOrder) do
                    local icon = markerTextures[name] or ""
                    info.text = icon .. "  " .. name   -- icon + label
                    info.value = name
                    info.func = MarkerDropdown_OnClick
                    info.checked = (db.selectedMarker == name)
                    UIDropDownMenu_AddButton(info)
                end
            end)


            if UIDropDownMenu_SetWidth then
                UIDropDownMenu_SetWidth(dropdown, 160)
            end
            if UIDropDownMenu_SetSelectedValue then
                UIDropDownMenu_SetSelectedValue(dropdown, db.selectedMarker or globalDefaults.selectedMarker)
            end
        else
            local warn = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            warn:SetPoint("TOPLEFT", markerLabel, "BOTTOMLEFT", 0, -8)
            warn:SetText("Dropdown API unavailable in this client. Use /focusmarker to change the marker.")
        end

        ----------------------------------------------------------------
        -- Checkbox: announce to party on ready check
        ----------------------------------------------------------------
        if db.announceReadyCheck == nil then
            db.announceReadyCheck = true
        end

        local checkbox = CreateFrame("CheckButton", "FocusMarkerOptionsAnnounceCheck", self, "ChatConfigCheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 15, -20)
        checkbox.Text:SetText("Announce marker in party chat on ready check")
        checkbox:SetChecked(db.announceReadyCheck)

        checkbox:SetScript("OnClick", function(btn)
            db.announceReadyCheck = btn:GetChecked() and true or false
        end)

        FocusMarkerOptions.announceCheckbox = checkbox

        ----------------------------------------------------------------
        -- Checkbox: mark only (no focus)
        ----------------------------------------------------------------
        if db.markOnly == nil then
            db.markOnly = false
        end

        local markOnlyCheckbox = CreateFrame("CheckButton", "FocusMarkerOptionsMarkOnlyCheck", self, "ChatConfigCheckButtonTemplate")
        markOnlyCheckbox:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 0, -2)
        markOnlyCheckbox.Text:SetText("Only mark target (do not set focus)")
        markOnlyCheckbox:SetChecked(db.markOnly)

        markOnlyCheckbox:SetScript("OnClick", function(btn)
            db.markOnly = btn:GetChecked() and true or false

            local markerName = db.selectedMarker or globalDefaults.selectedMarker
            local idx = nameToIndex[markerName] or 0
            local body = BuildMacroBodyForIndex(idx)
            local icon = GetCurrentMacroIcon()
            local macroName = db.macroName or MACRO_NAME

            if not InCombatLockdown() then
                local ok, err = ApplyMacroNow(macroName, icon, body)
                if not ok and err == "incombat" then
                    QueueMacroUpdate(macroName, icon, body)
                end
            else
                QueueMacroUpdate(macroName, icon, body)
            end
        end)

        FocusMarkerOptions.markOnlyCheckbox = markOnlyCheckbox

        ----------------------------------------------------------------
        -- Checkbox: Don't mark in raid
        ----------------------------------------------------------------
        if db.noRaid == nil then
            db.noRaid = false
        end

        local noRaidCheckbox = CreateFrame("CheckButton", "FocusMarkerOptionsNoRaidCheck", self, "ChatConfigCheckButtonTemplate")
        noRaidCheckbox:SetPoint("TOPLEFT", markOnlyCheckbox, "BOTTOMLEFT", 0, -2)
        noRaidCheckbox.Text:SetText("Don't mark target while in raid group")
        noRaidCheckbox:SetChecked(db.noRaid)

        noRaidCheckbox:SetScript("OnClick", function(btn)
            db.noRaid = btn:GetChecked() and true or false

            local markerName = db.selectedMarker or globalDefaults.selectedMarker
            local idx = nameToIndex[markerName] or 0
            local body = BuildMacroBodyForIndex(idx)
            local icon = GetCurrentMacroIcon()
            local macroName = db.macroName or MACRO_NAME

            if not InCombatLockdown() then
                local ok, err = ApplyMacroNow(macroName, icon, body)
                if not ok and err == "incombat" then
                    QueueMacroUpdate(macroName, icon, body)
                end
            else
                QueueMacroUpdate(macroName, icon, body)
            end
        end)

        FocusMarkerOptions.noRaidCheckbox = noRaidCheckbox

        ----------------------------------------------------------------
        -- Edit box: Macro conditionals
        ----------------------------------------------------------------
        local conditionalsLabel = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        conditionalsLabel:SetPoint("TOPLEFT", noRaidCheckbox, "BOTTOMLEFT", 5, -20)
        conditionalsLabel:SetText("Macro conditionals:")

        local conditionalsEditBox = CreateFrame("EditBox", "FocusMarkerOptionsConditionalsEditBox", self, "InputBoxTemplate")
        conditionalsEditBox:SetSize(200, 20)
        conditionalsEditBox:SetPoint("LEFT", conditionalsLabel, "RIGHT", 10, 0)
        conditionalsEditBox:SetAutoFocus(false)
        conditionalsEditBox:SetText(db.macroConditionals or MACRO_CONDITIONALS_DEFAULT)

        local conditionalsButton = CreateFrame("Button", "FocusMarkerOptionsConditionalReset", self, "UIPanelButtonTemplate")
        conditionalsButton:SetSize(130, 24)
        conditionalsButton:SetPoint("LEFT", conditionalsEditBox, "RIGHT", 4, 0)
        conditionalsButton:SetText("Default Conditionals")

        local function RebuildMacroWithCurrentSettings()
            local markerName = db.selectedMarker or globalDefaults.selectedMarker
            local idx = nameToIndex[markerName] or 0
            local body = BuildMacroBodyForIndex(idx)
            local icon = GetCurrentMacroIcon()
            local macroName = db.macroName or MACRO_NAME

            if not InCombatLockdown() then
                local ok, err = ApplyMacroNow(macroName, icon, body)
                if not ok and err == "incombat" then
                    QueueMacroUpdate(macroName, icon, body)
                end
            else
                QueueMacroUpdate(macroName, icon, body)
            end
        end

        local function SaveConditionalsFromEditBox()
            local txt = conditionalsEditBox:GetText() or ""
            if txt == "" then
                -- empty means "use default"
                db.macroConditionals = nil
            else
                db.macroConditionals = txt
            end
            RebuildMacroWithCurrentSettings()
        end

        conditionalsEditBox:SetScript("OnEnterPressed", function(selfEdit)
            SaveConditionalsFromEditBox()
            selfEdit:ClearFocus()
        end)

        conditionalsEditBox:SetScript("OnEditFocusLost", function(selfEdit)
            SaveConditionalsFromEditBox()
        end)

        conditionalsButton:SetScript("OnClick", function()
            conditionalsEditBox:SetText(MACRO_CONDITIONALS_DEFAULT)
            db.macroConditionals = nil 
            RebuildMacroWithCurrentSettings()
        end)

        ----------------------------------------------------------------
        -- Edit box: Macro name
        ----------------------------------------------------------------
        local nameLabel = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        nameLabel:SetPoint("TOPLEFT", conditionalsLabel, "BOTTOMLEFT", 0, -30)
        nameLabel:SetText("Macro name:")

        local nameEditBox = CreateFrame("EditBox", "FocusMarkerOptionsNameEditBox", self, "InputBoxTemplate")
        nameEditBox:SetSize(140, 20)
        nameEditBox:SetMaxLetters(16)
        nameEditBox:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
        nameEditBox:SetAutoFocus(false)

        -- initial value
        nameEditBox:SetText(db.macroName or MACRO_NAME)

        local function SaveNameFromEditBox()
            local oldName = db.macroName or MACRO_NAME

            local txt = nameEditBox:GetText()
            if not txt or txt == "" then
                db.macroName = MACRO_NAME   -- fallback
            else
                db.macroName = txt
            end

            local newName = db.macroName

            -- update macro immediately (or queue)
            local marker = db.selectedMarker or globalDefaults.selectedMarker
            local idx = nameToIndex[marker] or 0
            local body = BuildMacroBodyForIndex(idx)
            local icon = GetCurrentMacroIcon()

            if not InCombatLockdown() then
                local ok, err = ApplyMacroNow(newName, icon, body, oldName)
                if not ok and err == "incombat" then
                    QueueMacroUpdate(newName, icon, body, oldName)
                end
            else
                QueueMacroUpdate(newName, icon, body, oldName)
            end
        end

        nameEditBox:SetScript("OnEnterPressed", function(selfEdit)
            SaveNameFromEditBox()
            selfEdit:ClearFocus()
        end)

        nameEditBox:SetScript("OnEditFocusLost", function(selfEdit)
            SaveNameFromEditBox()
        end)

        FocusMarkerOptions.nameEditBox = nameEditBox


        ----------------------------------------------------------------
        -- Edit box: macro icon ID
        ----------------------------------------------------------------
        local iconLabel = self:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        iconLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", -1, -9)
        iconLabel:SetText("Macro icon ID:")

        local editBox = CreateFrame("EditBox", "FocusMarkerOptionsIconEditBox", self, "InputBoxTemplate")
        editBox:SetSize(80, 20)
        editBox:SetPoint("LEFT", iconLabel, "RIGHT", 10, 0)
        editBox:SetAutoFocus(false)

        -- default to current saved icon or MACRO_ICON
        local currentIconId = db.macroIconId or MACRO_ICON
        if currentIconId then
            editBox:SetText(tostring(currentIconId))
        end

        local function SaveIconFromEditBox()
            local txt = editBox:GetText()
            if not txt or txt == "" then
                db.macroIconId = nil
            else
                local num = tonumber(txt)
                if num then
                    db.macroIconId = num
                else
                    editBox:SetText(tostring(db.macroIconId or MACRO_ICON or ""))
                    return
                end
            end

            -- optional: immediately re-apply macro with new icon
            if not InCombatLockdown() then
                local markerName = db.selectedMarker or globalDefaults.selectedMarker
                local idx = nameToIndex[markerName] or 0
                local body = BuildMacroBodyForIndex(idx)
                local icon = GetCurrentMacroIcon()
                local ok, err = ApplyMacroNow(db.macroName or MACRO_NAME, icon, body)
                if not ok and err == "incombat" then
                    QueueMacroUpdate(db.macroName or MACRO_NAME, icon, body)
                end
            end
        end

        editBox:SetScript("OnEnterPressed", function(selfEdit)
            SaveIconFromEditBox()
            selfEdit:ClearFocus()
        end)

        editBox:SetScript("OnEditFocusLost", function(selfEdit)
            SaveIconFromEditBox()
        end)

        FocusMarkerOptions.iconEditBox = editBox

        -------------------------------------------------------------------
        -- Grey Descriptive Text
        -------------------------------------------------------------------
        local hint = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 3, -8)
        hint:SetJustifyH("LEFT")
        hint:SetText("This only accepts Icon ID's. \n" ..
                    "Wowhead can show you icon ID's by navigating to an ability and clicking on the icon.\n" ..
                     "PS: My personal preference is 132177 (The 'Master Marksman' icon).")

        local hintMaxCharacters = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hintMaxCharacters:SetPoint("LEFT", nameEditBox, "RIGHT", 4, 0)
        hintMaxCharacters:SetText("(Max 16 characters)")
    end)

    -------------------------------------------------------------------
    -- Register with Settings / Interface Options
    -------------------------------------------------------------------
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    else
        -- Something is wrong and can't make the options menu. AKA fuck handling multiple client versions. 
        if not FocusMarkerOptions_NoInterfaceOptionsWarning then
            FocusMarkerOptions_NoInterfaceOptionsWarning = true
            print("|cffffff00[FocusMarker]|r Unable to register options panel: no Settings or InterfaceOptions API found.")
        end
    end
end
