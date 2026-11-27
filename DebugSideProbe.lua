-- Debug only, not for release (.pkgmeta). Measures where your character sits
-- on screen for a side offset: at each of ZOOMS, sends test_cameraOverShoulder
-- each of SHARES of the zoom (in yards, past the side slider's
-- SIDE_YARDS_AT_FULL too), waits for the camera to settle, saves what the game
-- took (test_cameraOverShoulder, the zoom), where your own nameplate (the
-- Personal Resource Display, turned on for the run) is across the screen, and
-- takes a screenshot (the game's Screenshots folder). Then, at MAX_ZOOM, each
-- of MAX_YARDS: how far the game lets the camera go (what it takes back, and
-- whether the picture still moves). Then it puts your side
-- offset, zoom and nameplate settings back and shows a reload box that writes
-- GamepadCameraOffsetDebugDB.sideProbe.
-- Runs by itself a few seconds after a login when RUN_ID changed (bump it to
-- measure again after the next reload); /gpco debug side runs it now. A fight
-- stops it; your side offset and nameplate settings come back, after a reload
-- mid-run too.
local Camera = _G.GamepadCameraOffset

local DebugSideProbe = {
    RUN_ID = 8,
    START_SECONDS = 6,
    SETTLE_SECONDS = 2.5,
    AFTER_SHOT_SECONDS = 0.5,   -- the shot is taken before the camera moves on
    -- Measured in RUN_ID 5 (zooms 5, 10, 20: KeepOnScreen.lua's limit); empty to skip.
    ZOOMS = {},
    SHARES = { 0, 0.3, 0.6 },   -- side offset in yards = share * zoom
    MAX_ZOOM = 10,
    -- RUN_ID 5: the picture moved up to 100, and was the same from 1000 to 10000.
    -- RUN_ID 6 (every 125): it moved up to 250; from 375 the camera was back
    -- near your character, the same picture from 500 to 1000.
    -- RUN_ID 7 (every 16): the camera jumped back between 250 and 266.
    -- Every 2 between, every 1 around 256.
    MAX_YARDS = { 250, 252, 254, 255, 256, 257, 258, 260, 262, 264, 266 },
    -- Your own nameplate, on for the run: it follows your character across the screen.
    NAMEPLATE_CVARS = { nameplateShowSelf = "1", nameplatePersonalShowAlways = "1" },
}
Camera.DebugSideProbe = DebugSideProbe

local probe   -- the run in progress, or nil

local timerText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
timerText:SetPoint("TOPLEFT", 12, -12)

local function getDebugStore()
    if type(GamepadCameraOffsetDebugDB) ~= "table" then GamepadCameraOffsetDebugDB = {} end
    return GamepadCameraOffsetDebugDB
end

-- Every camera CVar the game lists, with its value, to see what else moves the camera.
local function cameraCVars()
    local values = {}
    local console = _G.C_Console
    if type(console) ~= "table" or type(console.GetAllCommands) ~= "function" then return values end
    local succeeded, commands = pcall(console.GetAllCommands)
    if not succeeded or type(commands) ~= "table" then return values end
    for _, command in ipairs(commands) do
        local name = command.command
        if type(name) == "string" and name:lower():find("camera") then
            values[name] = Camera.GetCVar(name)
        end
    end
    return values
end

-- Every function the game has with "camera" in its name: globals, and the
-- members of its C_ namespaces. Looking for one that says where the camera is.
local function cameraFunctions()
    local names = {}
    for name, value in pairs(_G) do
        if type(name) == "string" then
            if type(value) == "function" and name:lower():find("camera") then
                names[#names + 1] = name
            elseif type(value) == "table" and name:find("^C_") then
                for memberName, member in pairs(value) do
                    if type(memberName) == "string" and type(member) == "function"
                        and (name:lower():find("camera") or memberName:lower():find("camera")) then
                        names[#names + 1] = name .. "." .. memberName
                    end
                end
            end
        end
    end
    table.sort(names)
    return names
end

-- The game's "Screen captured" line stays out of the next shot.
local savedActionStatusAlpha
local function hideScreenCapturedMessage(hidden)
    if not ActionStatus then return end
    if hidden then
        savedActionStatusAlpha = ActionStatus:GetAlpha()
        ActionStatus:SetAlpha(0)
    else
        ActionStatus:SetAlpha(savedActionStatusAlpha or 1)
    end
end

local function setCVar(name, value)
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    pcall(setter, name, tostring(value))
end

local function zoomTo(zoom)
    local change = zoom - GetCameraZoom()
    if change > 0 then pcall(CameraZoomOut, change) elseif change < 0 then pcall(CameraZoomIn, -change) end
end

-- Your side offset, nameplate settings and zoom, as they were before the run.
local function putSettingsBack(run)
    if run.sideToRestore ~= nil then
        Camera.OffsetKeys.SetSide(run.sideToRestore)
        run.sideToRestore = nil
    end
    for name, value in pairs(run.cvarsToRestore or {}) do setCVar(name, value) end
    run.cvarsToRestore = nil
    if run.zoomToRestore then zoomTo(run.zoomToRestore) end
    run.zoomToRestore = nil
end

-- Where your own nameplate's center is across the screen: -1 the left edge,
-- 0 the center, 1 the right edge; nil without one.
local function nameplateAcross()
    local namePlates = _G.C_NamePlate
    if type(namePlates) ~= "table" or type(namePlates.GetNamePlateForUnit) ~= "function" then return nil end
    local succeeded, namePlate = pcall(namePlates.GetNamePlateForUnit, "player")
    if not succeeded or not namePlate or not namePlate:IsVisible() then return nil end
    local x = namePlate:GetCenter()
    if not x then return nil end
    local screenWidth = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    return (x * namePlate:GetEffectiveScale() - screenWidth / 2) / (screenWidth / 2)
end

-- Every (zoom, yards) pair to measure, in order.
local function measurements()
    local list = {}
    for _, zoom in ipairs(DebugSideProbe.ZOOMS) do
        for _, share in ipairs(DebugSideProbe.SHARES) do
            list[#list + 1] = { zoom = zoom, yards = share * zoom }
        end
    end
    for _, yards in ipairs(DebugSideProbe.MAX_YARDS) do
        list[#list + 1] = { zoom = DebugSideProbe.MAX_ZOOM, yards = yards }
    end
    return list
end

local function finish(stopReason)
    local run = probe
    probe = nil
    run.stopped = stopReason
    putSettingsBack(run)
    timerText:SetText("")
    hideScreenCapturedMessage(false)
    Camera.Popup.Show({ text = "Side offset measured.\n\nReload to save it.",
        buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

-- The side slider at its end on that side turns the offsets on (ActionCam);
-- then the yards go straight to the CVar, past what the slider sends.
local function sendYards(yards)
    local sidePercent = (yards > 0 and Camera.SIDE_MAX) or (yards < 0 and Camera.SIDE_MIN) or 0
    Camera.OffsetKeys.SetSide(sidePercent)
    Camera.KeepOnScreen.Stop()   -- it would put back the yards it limits
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    pcall(setter, Camera.CVAR_OVER_SHOULDER, tostring(yards))
end

local function measure(index)
    if not probe then return end
    local list = measurements()
    local measurement = list[index]
    if measurement == nil then return finish() end
    local yards = measurement.yards
    zoomTo(measurement.zoom)
    sendYards(yards)
    local tookAtOnce = Camera.GetCVar(Camera.CVAR_OVER_SHOULDER)
    local secondsLeft = (#list - index + 1) * (DebugSideProbe.SETTLE_SECONDS + DebugSideProbe.AFTER_SHOT_SECONDS)
    timerText:SetText(string.format("Side offset test: %d s left. Don't move.", math.ceil(secondsLeft)))
    C_Timer.After(DebugSideProbe.SETTLE_SECONDS, function()
        if not probe then return end
        probe.shots[#probe.shots + 1] = {
            yardsSent = yards,
            overShoulderAtOnce = tookAtOnce,
            overShoulder = Camera.GetCVar(Camera.CVAR_OVER_SHOULDER),
            zoomSent = measurement.zoom,
            zoom = GetCameraZoom(),
            nameplateAcross = nameplateAcross(),
            time = date("%H:%M:%S"),
        }
        Screenshot()
        C_Timer.After(DebugSideProbe.AFTER_SHOT_SECONDS, function() measure(index + 1) end)
    end)
end

function DebugSideProbe.Start()
    if probe then return end
    if InCombatLockdown() then return print("|cff88ccffgco debug|r side probe: not in combat") end
    local cvarsToRestore = {}
    for name in pairs(DebugSideProbe.NAMEPLATE_CVARS) do cvarsToRestore[name] = Camera.GetCVar(name) end
    probe = {
        runID = DebugSideProbe.RUN_ID,   -- saved from the start: a reload mid-run doesn't run it again
        time = date("%Y-%m-%d %H:%M:%S"),
        sideToRestore = Camera.GetSettings().side,
        cvarsToRestore = cvarsToRestore,
        zoomToRestore = GetCameraZoom(),
        screenAspect = GetScreenWidth() / GetScreenHeight(),
        tilt = Camera.GetSettings().tilt,
        screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale(),
        cameraCVars = cameraCVars(),
        cameraFunctions = cameraFunctions(),
        shots = {},
    }
    getDebugStore().sideProbe = probe
    for name, value in pairs(DebugSideProbe.NAMEPLATE_CVARS) do setCVar(name, value) end
    hideScreenCapturedMessage(true)
    measure(1)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- A reload during a run left test settings in: put yours back.
        local lastRun = getDebugStore().sideProbe
        if lastRun then putSettingsBack(lastRun) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
        local lastRun = getDebugStore().sideProbe
        if lastRun and lastRun.runID == DebugSideProbe.RUN_ID then return end
        timerText:SetText(string.format("Side offset test starts in %d s. Don't move.", DebugSideProbe.START_SECONDS))
        C_Timer.After(DebugSideProbe.START_SECONDS, DebugSideProbe.Start)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if probe then finish("combat") end
    end
end)
