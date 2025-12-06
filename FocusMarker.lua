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

-- saved variables table (will be created by WoW when the addon is loaded)
if not _G[SAVEDVARS] then
    _G[SAVEDVARS] = {}
end
local db = _G[SAVEDVARS]

-- ensure defaults
if not db.selectedMarker then
    db.selectedMarker = globalDefaults.selectedMarker
end

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
    local ok, err = ApplyMacroNow(MACRO_NAME, MACRO_ICON, body)
    if not ok then
        if err == "incombat" then
            QueueMacroUpdate(MACRO_NAME, MACRO_ICON, body)
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
        print("|cffffff00["..ADDON_NAME.."]|r Usage: /focusmarker <name|alias|number>  (e.g. /focusmarker star  or /focusmarker 1 or /focusmarker off)")
        return
    end
    -- take first token
    local first = strsplit(" ", msg)
    SetSelectedMarkerByName(first)
end

-- Interface Options panel (safe / defensive version)
do
    local container = _G.InterfaceOptionsFramePanelContainer or nil
    local panel = CreateFrame("Frame", "FocusMarkerOptions", container)
    panel.name = "FocusMarker"
    panel:Hide()

    panel:SetScript("OnShow", function(self)
        if not self.initialized then
            self.initialized = true

            -- Title
            local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 16, -16)
            title:SetText("FocusMarker")

            -- Description
            local desc = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
            desc:SetText("This addon edits a macro named 'FocusMarker' to apply the configured raid target index.\nUse the dropdown below or the slash command: /focusmarker <name|alias|number>\nMacro body will be:\n/focus [@mouseover,exists,nodead][]\n/tm [@mouseover,exists,nodead][] <N>\nNote: macro updates only occur when you change the configured marker (via UI or /focusmarker).")

            -- Dropdown label
            local label = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
            label:SetText("Selected marker:")

            if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo then
                local dd = CreateFrame("Frame", "FocusMarkerDropdown", self, "UIDropDownMenuTemplate")
                dd:SetPoint("LEFT", label, "RIGHT", 14, 3)
                dd:SetScript("OnShow", function()
                    if UIDropDownMenu_SetSelectedValue then
                        UIDropDownMenu_SetSelectedValue(dd, db.selectedMarker or globalDefaults.selectedMarker)
                    end
                end)
                FocusMarkerOptions = FocusMarkerOptions or {}
                FocusMarkerOptions.dropdown = dd

                local function Dropdown_OnClick(self)
                    local value = self.value
                    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dd, value) end
                    SetSelectedMarkerByName(value)
                end

                UIDropDownMenu_Initialize(dd, function(frame, level, menuList)
                    local info = UIDropDownMenu_CreateInfo()
                    for _,name in ipairs(optionsOrder) do
                        info.text = name
                        info.func = Dropdown_OnClick
                        info.value = name
                        info.checked = (db.selectedMarker == name)
                        UIDropDownMenu_AddButton(info)
                    end
                end)

                if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, 160) end
                if UIDropDownMenu_SetSelectedValue then
                    UIDropDownMenu_SetSelectedValue(dd, db.selectedMarker or globalDefaults.selectedMarker)
                end
            else
                local warning = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                warning:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
                warning:SetText("Dropdown UI failed. Use /focusmarker <name|alias|number> to configure.")
            end
        end
    end)

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    else
        if not FocusMarkerOptions_RegisteredWarningShown then
            print("|cffffff00[FocusMarker]|r Interface Options failed. Use /focusmarker <name|alias|number> to configure.")
            FocusMarkerOptions_RegisteredWarningShown = true
        end
    end
end
