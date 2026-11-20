-- Nameplates for "Crosshair on your target": the crosshair goes under the target's
-- nameplate, so without one (friendly player nameplates are off by default) it
-- stays where the game aims. On first launch, if any nameplate setting it uses is
-- off, a box says which and offers to turn them on. Nothing changes without its
-- "Turn on". Asked once; the settings page has a button to ask again.
--
-- The settings are the game's own CVars, as its Options > Nameplates page sets
-- them (forever branch, Blizzard_SettingsDefinitions_Frame/Nameplates.lua:467,
-- :487, :826-848). They can't be changed in combat: the box waits for the fight's
-- end. If they still don't take, "Crosshair on your target" is switched off, and
-- the box says why.
local Camera = _G.GamepadCameraOffset

local Nameplates = {
    -- { CVar, what the box calls it }
    SETTINGS = {
        { "nameplateShowEnemies", "enemy nameplates" },
        { "nameplateShowFriendlyPlayers", "friendly player nameplates" },
        { "nameplateShowFriendlyClassColor", "class colors on friendly player nameplates" },
    },
}
Camera.Nameplates = Nameplates

-- The nameplate settings that are off now: a list of { cvar, label }.
function Nameplates.Missing()
    local missing = {}
    for _, entry in ipairs(Nameplates.SETTINGS) do
        local value = Camera.GetCVar(entry[1])
        if value ~= nil and value ~= "1" then missing[#missing + 1] = entry end
    end
    return missing
end

local function labels(entries)
    local names = {}
    for _, entry in ipairs(entries) do names[#names + 1] = entry[2] end
    return table.concat(names, ", ")
end

local box

local function closeBox() if box then box:Hide() end end

-- Turns the missing settings on, then checks they took; if not, the crosshair
-- setting that needs them goes off.
function Nameplates.TurnOn()
    for _, entry in ipairs(Nameplates.Missing()) do
        if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, entry[1], "1") else pcall(SetCVar, entry[1], "1") end
    end
    local stillMissing = Nameplates.Missing()
    if #stillMissing > 0 then
        Camera.GetSettings().crosshair = false
        Camera.Apply()
        print("|cff88ccffGamepad Camera Offset|r couldn't turn on " .. labels(stillMissing)
            .. ", so \"Crosshair on your target\" is off. Turn them on in Options > Nameplates, then turn it back on.")
        return false
    end
    print("|cff88ccffGamepad Camera Offset|r turned on the nameplates the crosshair uses.")
    return true
end

local function buildBox()
    box = CreateFrame("Frame", "GamepadCameraOffsetNameplatesBox", UIParent)
    box:SetSize(420, 150)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    box:SetFrameStrata("DIALOG")
    box:EnableMouse(true)
    local background = box:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.85)
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.text:SetPoint("TOP", box, "TOP", 0, -14)
    box.text:SetWidth(390)
    box.turnOnButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.turnOnButton:SetSize(150, 24)
    box.turnOnButton:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 40, 14)
    box.turnOnButton:SetText("Turn on")
    box.turnOnButton:SetScript("OnClick", function()
        closeBox()
        if InCombatLockdown() then return Nameplates.Ask() end   -- after the fight
        Nameplates.TurnOn()
    end)
    box.noButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.noButton:SetSize(150, 24)
    box.noButton:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -40, 14)
    box.noButton:SetText("No thanks")
    box.noButton:SetScript("OnClick", closeBox)
    Nameplates.box = box
end

-- Shows the box if a setting is off (out of combat; in one, after it).
-- Returns whether it showed.
function Nameplates.Ask()
    local missing = Nameplates.Missing()
    if #missing == 0 then return false end
    if InCombatLockdown() then
        Nameplates.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    if not box then buildBox() end
    box.text:SetText("Gamepad Camera Offset\n\n\"Crosshair on your target\" puts the crosshair under your "
        .. "target's nameplate. These are off: " .. labels(missing) .. ".\nTurn them on? (Options > Nameplates)")
    box:Show()
    return true
end

-- On first launch, once: only when the crosshair setting that needs them is on.
local function askOnFirstLaunch()
    local settings = Camera.GetSettings()
    if settings.nameplatesAsked or not (settings.enabled and settings.crosshair) then return end
    if #Nameplates.Missing() == 0 then return end
    settings.nameplatesAsked = true   -- asked now, or after the fight if in one
    Nameplates.Ask()
end

-- The settings page's button (GamepadCameraOffset.lua calls this while building it).
function Camera.AddNameplatesButton(layout)
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    layout:AddInitializer(CreateSettingsButtonInitializer("Nameplates", "Turn on nameplates...",
        function()
            if not Nameplates.Ask() then print("|cff88ccffGamepad Camera Offset|r the nameplates it uses are already on.") end
        end,
        "\"Crosshair on your target\" uses the target's nameplate: enemy and friendly player nameplates, "
        .. "and class colors on friendly ones. Asks before turning on any that are off.", true))
end

Nameplates.eventFrame = CreateFrame("Frame")
Nameplates.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
Nameplates.eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        askOnFirstLaunch()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Nameplates.Ask()
    end
end)
