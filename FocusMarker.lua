local ADDON_NAME = "FocusMarker"
local SAVEDVARS = "AryFocusMarkerDB"
local MACRO_NAME = "FocusMarker"
local MACRO_ICON = 132327

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

-- canonical options and lookup to raid target index
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

local markerTextures = {
    Star     = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:16|t",
    Circle   = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_2:16|t",
    Diamond  = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:16|t",
    Triangle = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_4:16|t",
    Moon     = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_5:16|t",
    Square   = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_6:16|t",
    Cross    = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_7:16|t",
    Skull    = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:16|t",
    None     = "|TInterface\\Buttons\\UI-GroupLoot-Pass-Up:16|t", -- visual placeholder
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

    -- Optional: debug print to confirm it's working
    -- print("|cffffff00[FocusMarker]|r Loaded marker:", db.selectedMarker)
end)


-- Pending macro update state (used when macro APIs are protected during combat)
local pendingMacroName = nil
local pendingMacroIcon = nil
local pendingMacroBody = nil
local pendingMacroQueued = false

-- Frame to handle queued regen events
local queuedFrame = CreateFrame("Frame", ADDON_NAME .. "QueuedFrame")
queuedFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Try to apply pending macro when combat ends
        if pendingMacroQueued and not InCombatLockdown() then
            local ok, err = pcall(function()
                local mIndex = GetMacroIndexByName(pendingMacroName)
                if mIndex and mIndex > 0 then
                    EditMacro(mIndex, pendingMacroName, pendingMacroIcon, pendingMacroBody)
                else
                    CreateMacro(pendingMacroName, pendingMacroIcon, pendingMacroBody, nil)
                end
            end)
            if ok then
                pendingMacroQueued = false
                pendingMacroName = nil
                pendingMacroIcon = nil
                pendingMacroBody = nil
                queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
                print("|cffffff00["..ADDON_NAME.."]|r Macro '"..MACRO_NAME.."' updated after combat.")
            else
                -- If still failing for non-combat reason, clear to avoid infinite retries
                print("|cffffff00["..ADDON_NAME.."]|r Failed to update macro after combat: "..tostring(err))
                pendingMacroQueued = false
                pendingMacroName = nil
                pendingMacroIcon = nil
                pendingMacroBody = nil
                queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
    end
end)

-- Build the macro body given an index (0..8)
local function BuildMacroBodyForIndex(idx)
    local line1 = "/focus [@mouseover,exists,nodead][]"
    local line2 = "/tm [@mouseover,exists,nodead][] " .. tostring(idx)
    return line1 .. "\n" .. line2
end

-- Helper function that gets the currently set icon.
local function GetCurrentMacroIcon()
    if db and db.macroIconId then
        return db.macroIconId
    end
    return MACRO_ICON
end


-- Try to create or edit macro now; returns true on success, false and err on failure.
local function ApplyMacroNow(name, icon, body)
    if InCombatLockdown() then
        return false, "incombat"
    end

    local ok, err = pcall(function()
        local mIndex = GetMacroIndexByName(name)
        if mIndex and mIndex > 0 then
            EditMacro(mIndex, name, icon, body)
        else
            CreateMacro(name, icon, body, nil) -- global macro
        end
    end)

    if not ok then
        return false, err
    end

    return true
end

-- Queue a macro update to run after combat ends
local function QueueMacroUpdate(name, icon, body)
    pendingMacroName = name
    pendingMacroIcon = icon
    pendingMacroBody = body
    pendingMacroQueued = true
    queuedFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    print("|cffffff00["..ADDON_NAME.."]|r In combat: will update macro after combat.")
end

-- Attempt to apply pending macro (safe-guard; used from event handlers)
local function TryApplyPendingMacro()
    if not pendingMacroQueued then return end
    if InCombatLockdown() then return end

    local ok, err = ApplyMacroNow(pendingMacroName, pendingMacroIcon, pendingMacroBody)
    if ok then
        pendingMacroQueued = false
        pendingMacroName = nil
        pendingMacroIcon = nil
        pendingMacroBody = nil
        queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        print("|cffffff00["..ADDON_NAME.."]|r Macro updated after combat.")
    else
        if err ~= "incombat" then
            print("|cffffff00["..ADDON_NAME.."]|r Failed to update macro: "..tostring(err))
            -- clear queue to avoid infinite retry on non-combat errors
            pendingMacroQueued = false
            pendingMacroName = nil
            pendingMacroIcon = nil
            pendingMacroBody = nil
            queuedFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        -- if still in combat, do nothing — wait for next regen event
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
    local ok, err = ApplyMacroNow(MACRO_NAME, GetCurrentMacroIcon(), body)
    if not ok then
        if err == "incombat" then
            QueueMacroUpdate(MACRO_NAME, GetCurrentMacroIcon(), body)
        else
            print("|cffffff00["..ADDON_NAME.."]|r Failed to create/update macro '"..MACRO_NAME.."': "..tostring(err))
        end
    end

    -- update dropdown value if present
    if FocusMarkerOptions and FocusMarkerOptions.dropdown and UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(FocusMarkerOptions.dropdown, canonical)
    end
end

-- Slash command
SLASH_FOCUSMARKER1 = "/focusmarker"
SlashCmdList["FOCUSMARKER"] = function(msg)
    msg = msg and strtrim(msg) or ""
    if msg == "" then
        print("|cffffff00["..ADDON_NAME.."]|r Current marker: "..(db.selectedMarker or globalDefaults.selectedMarker))
        print("|cffffff00["..ADDON_NAME.."]|r Usage: /focusmarker <name/number>  (e.g. /focusmarker star  or /focusmarker 1)")
        print("|cffffff00["..ADDON_NAME.."]|r Open Addon Menu for more options.")
        return
    end
    -- take first token
    local first = strsplit(" ", msg)
    SetSelectedMarkerByName(first)
end

-----------------------------------------------------------------------
-- Options panel (Settings UI + legacy Interface Options fallback)
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

        ----------------------------------------------------------------
        -- Title & description
        ----------------------------------------------------------------
        local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("FocusMarker")

        local desc = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        desc:SetJustifyH("LEFT")
        desc:SetText("Configure the FocusMarker addon.\n" ..
                     "• Select which raid marker your FocusMarker macro uses.\n" ..
                     "• Toggle announcing your marker in party chat on ready check.\n" ..
                     "• Set the macro icon ID (currently just saved, wiring comes later).")

        ----------------------------------------------------------------
        -- Marker dropdown
        ----------------------------------------------------------------
        local markerLabel = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        markerLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
        markerLabel:SetText("Selected marker:")

        local dropdown = CreateFrame("Frame", "FocusMarkerOptionsMarkerDropdown", self, "UIDropDownMenuTemplate")
        dropdown:SetPoint("LEFT", markerLabel, "RIGHT", 16, -3)

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
            local warn = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            warn:SetPoint("TOPLEFT", markerLabel, "BOTTOMLEFT", 0, -8)
            warn:SetText("Dropdown API unavailable in this client. Use /focusmarker to change the marker.")
        end

        ----------------------------------------------------------------
        -- Checkbox: announce to party on ready check
        ----------------------------------------------------------------
        if db.announceReadyCheck == nil then
            db.announceReadyCheck = true -- default ON; behavior wiring later
        end

        local checkbox = CreateFrame("CheckButton", "FocusMarkerOptionsAnnounceCheck", self, "InterfaceOptionsCheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", markerLabel, "BOTTOMLEFT", 0, -32)
        checkbox.Text:SetText("Announce marker in party chat on ready check")
        checkbox:SetChecked(db.announceReadyCheck)

        checkbox:SetScript("OnClick", function(btn)
            db.announceReadyCheck = btn:GetChecked() and true or false
        end)

        FocusMarkerOptions.announceCheckbox = checkbox

        ----------------------------------------------------------------
        -- Edit box: macro icon ID
        ----------------------------------------------------------------
        local iconLabel = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        iconLabel:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 0, -18)
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
                local ok, err = ApplyMacroNow(MACRO_NAME, icon, body)
                if not ok and err == "incombat" then
                    QueueMacroUpdate(MACRO_NAME, icon, body)
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

        local hint = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -8)
        hint:SetJustifyH("LEFT")
        hint:SetText("This currently only saves the icon ID.\nMacro icon usage will be wired into the macro update logic later.")
    end)

    -------------------------------------------------------------------
    -- Register with Settings / Interface Options
    -------------------------------------------------------------------
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        -- Retail / modern clients: new Settings UI
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        category.ID = panel.name
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        -- Older / classic clients: legacy Interface Options
        InterfaceOptions_AddCategory(panel)
    else
        -- Neither API available (very unusual)
        if not FocusMarkerOptions_NoInterfaceOptionsWarning then
            FocusMarkerOptions_NoInterfaceOptionsWarning = true
            print("|cffffff00[FocusMarker]|r Unable to register options panel: no Settings or InterfaceOptions API found.")
        end
    end
end
