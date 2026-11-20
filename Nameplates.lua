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

-- One line each, as a list.
local function bulletList(entries)
    local lines = {}
    for _, entry in ipairs(entries) do lines[#lines + 1] = "• " .. entry[2] end
    return table.concat(lines, "\n")
end

local function labels(entries)
    local names = {}
    for _, entry in ipairs(entries) do names[#names + 1] = entry[2] end
    return table.concat(names, ", ")
end

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

-- Shows the popup (Popup.lua, the game's style) if a setting is off; in a fight,
-- the popup opens once it's over. Returns whether there was something to ask.
function Nameplates.Ask()
    local missing = Nameplates.Missing()
    if #missing == 0 then return false end
    Camera.Popup.Show({
        text = "Gamepad Camera Offset\n\n\"Crosshair on your target\" puts the crosshair under your target's nameplate. "
            .. "These are off:\n\n" .. bulletList(missing) .. "\n\nTurn them on? (Options > Nameplates)",
        buttons = {
            { text = "Turn on", onClick = function()
                if InCombatLockdown() then return Nameplates.Ask() end   -- after the fight
                Nameplates.TurnOn()
            end },
            { text = "No thanks" },
        },
    })
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
-- Added only if one of them is off when the page is built (each login or
-- reload): no function of ours for the game to call while it lays out the page.
-- A shown predicate (AddShownPredicate) did that, and from then on the
-- controller's navigation stayed stuck on the first row of our settings pages,
-- with no error (seen in game, 2026-11-20).
function Camera.AddNameplatesButton(layout)
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    if #Nameplates.Missing() == 0 then return end
    local initializer = CreateSettingsButtonInitializer("Nameplates", "Turn on nameplates",
        function()
            if not Nameplates.Ask() then print("|cff88ccffGamepad Camera Offset|r the nameplates it uses are already on.") end
        end,
        "\"Crosshair on your target\" uses the target's nameplate. It needs:\n\n"
        .. "• Enemy nameplates\n"
        .. "• Friendly player nameplates\n"
        .. "• Class colors on friendly ones\n\n"
        .. "Asks before turning on any that are off.", true)
    layout:AddInitializer(initializer)
end

Nameplates.eventFrame = CreateFrame("Frame")
Nameplates.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
Nameplates.eventFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    askOnFirstLaunch()
end)
