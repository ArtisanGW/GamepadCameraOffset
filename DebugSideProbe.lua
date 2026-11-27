-- Debug only, not for release (.pkgmeta). Measures how far the camera really
-- goes to each side: sends test_cameraOverShoulder each of YARDS (past the
-- side slider's SIDE_YARDS_AT_FULL too, to see where the game stops), waits for
-- the camera to settle, saves what the game took (test_cameraOverShoulder, the
-- zoom) and takes a screenshot (the game's Screenshots folder). Then it puts
-- your side offset back and shows a reload box that writes
-- GamepadCameraOffsetDebugDB.sideProbe.
-- Runs by itself a few seconds after a login when RUN_ID changed (bump it to
-- measure again after the next reload); /gpco debug side runs it now. A fight
-- stops it; your side offset comes back, after a reload mid-run too.
local Camera = _G.GamepadCameraOffset

local DebugSideProbe = {
    RUN_ID = 2,
    START_SECONDS = 6,
    SETTLE_SECONDS = 2.5,
    AFTER_SHOT_SECONDS = 0.5,   -- the shot is taken before the camera moves on
    YARDS = { 0, 3, 4.5, 6, 9, 12, 20, -6, -12 },
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

local function putSideBack(run)
    if run.sideToRestore == nil then return end
    Camera.OffsetKeys.SetSide(run.sideToRestore)
    run.sideToRestore = nil
end

local function finish(stopReason)
    local run = probe
    probe = nil
    run.stopped = stopReason
    run.runID = DebugSideProbe.RUN_ID
    putSideBack(run)
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
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    pcall(setter, Camera.CVAR_OVER_SHOULDER, tostring(yards))
end

local function measure(index)
    if not probe then return end
    local yards = DebugSideProbe.YARDS[index]
    if yards == nil then return finish() end
    sendYards(yards)
    local tookAtOnce = Camera.GetCVar(Camera.CVAR_OVER_SHOULDER)
    local secondsLeft = (#DebugSideProbe.YARDS - index + 1) * (DebugSideProbe.SETTLE_SECONDS + DebugSideProbe.AFTER_SHOT_SECONDS)
    timerText:SetText(string.format("Side offset test: %d s left. Don't move.", math.ceil(secondsLeft)))
    C_Timer.After(DebugSideProbe.SETTLE_SECONDS, function()
        if not probe then return end
        probe.shots[#probe.shots + 1] = {
            yardsSent = yards,
            overShoulderAtOnce = tookAtOnce,
            overShoulder = Camera.GetCVar(Camera.CVAR_OVER_SHOULDER),
            zoom = GetCameraZoom(),
            time = date("%H:%M:%S"),
        }
        Screenshot()
        C_Timer.After(DebugSideProbe.AFTER_SHOT_SECONDS, function() measure(index + 1) end)
    end)
end

function DebugSideProbe.Start()
    if probe then return end
    if InCombatLockdown() then return print("|cff88ccffgco debug|r side probe: not in combat") end
    probe = {
        time = date("%Y-%m-%d %H:%M:%S"),
        sideToRestore = Camera.GetSettings().side,
        tilt = Camera.GetSettings().tilt,
        screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale(),
        cameraCVars = cameraCVars(),
        shots = {},
    }
    getDebugStore().sideProbe = probe
    hideScreenCapturedMessage(true)
    measure(1)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- A reload during a run left a test side offset in: put yours back.
        local lastRun = getDebugStore().sideProbe
        if lastRun then putSideBack(lastRun) end
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
