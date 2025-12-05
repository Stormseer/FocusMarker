FocusMarker = FocusMarker or {}

local globalDefaults = {
    selectedMarker = "Star"
}

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


------------------------------------------------------------
-- Utility Functions
------------------------------------------------------------

local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function ucfirst(s)
    return s:sub(1,1):upper() .. s:sub(2):lower()
end

local function CreateHeader(parent, text, offsetY)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 16, offsetY)
    header:SetText(text)
    return header
end

------------------------------------------------------------
-- Create Options Panel
------------------------------------------------------------

local function CreateOptionsPanel()
    if panel then return end

    panel = CreateFrame("Frame", "FocusMarkerOptionsPanel", UIParent)
    panel.name = "FocusMarker"

    local mainCategory
    if Settings and Settings.RegisterCanvasLayoutCategory then
        mainCategory = Settings.RegisterCanvasLayoutCategory(panel, "FocusMarker", "FocusMarker")
        Settings.RegisterAddOnCategory(mainCategory)
    else
        InterfaceOptions_AddCategory(panel)
    end

    local function CreateSubpanel(title, builder)
        local sub = CreateFrame("Frame", "FocusMarker_Subpanel_" .. title:gsub("%s+", ""), UIParent)
        sub.name = title
        sub.parent = "FocusMarker"

        if builder then builder(sub) end

        if Settings and Settings.RegisterCanvasLayoutSubcategory and mainCategory then
            local subcat = Settings.RegisterCanvasLayoutSubcategory(mainCategory, sub, title)
            Settings.RegisterAddOnCategory(subcat)
        else
            InterfaceOptions_AddCategory(sub)
        end
    end
end

------------------------------------------------------------
-- Slash Command 
------------------------------------------------------------

SLASH_ARYUI1 = "/focusmarker"
SlashCmdList["ARYUI"] = function()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("FocusMarker")
    else
        if FocusMarkerOptionsPanel then
            InterfaceOptionsFrame_OpenToCategory(FocusMarkerOptionsPanel)
            InterfaceOptionsFrame_OpenToCategory(FocusMarkerOptionsPanel)
        end
    end
end


------------------------------------------------------------
-- ADDON LOAD HANDLER
------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon ~= "AryUI" then return end

    if not AryFocusMarkerDB then AryFocusMarkerDB = {} end
    ApplyDefaults(AryFocusMarkerDB, globalDefaults)

    -- Build options now
    CreateOptionsPanel()
end)
