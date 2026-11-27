-- /gpco debug: an in-game test suite. It runs through the settings one step at a
-- time (a step every Debug.SECONDS_BETWEEN_STEPS, so you can watch the camera
-- move), checks what the game actually took (the CVars),
-- puts your own settings back, and keeps the findings in
-- GamepadCameraOffsetDebugDB, which the game writes to disk on /reload or logout.
--   /gpco debug         runs the suite (out of combat)
--   /gpco debug last    prints the last run's findings again
--   /gpco debug clear   empties the saved runs
--   /gpco debug side    measures how far the camera goes to each side (DebugSideProbe.lua)
--   /gpco debug worldframe  whether moving the WorldFrame moves the picture up or down (DebugWorldFrameProbe.lua)
-- A fight stops the run (and puts your settings back). If a reload cuts a run
-- short, your settings are put back at the next login.

local Camera = _G.GamepadCameraOffset
local Debug = { SECONDS_BETWEEN_STEPS = 0.6, RUNS_KEPT = 10 }
Camera.Debug = Debug

-- Debug builds only: the other addon turned off in the AddOns list counts as
-- missing, so its "Get" button and popup show as players without it see them
-- (RelatedAddons.lua).
if Camera.RelatedAddons then Camera.RelatedAddons.countTurnedOffAsMissing = true end

local SETTING_KEYS = { "enabled", "side", "tilt", "lookDown", "keepOnScreen" }

local function say(text) print("|cff88ccffgco debug|r " .. text) end

-- Saved findings and the settings to put back

local function getDebugStore()
    if type(GamepadCameraOffsetDebugDB) ~= "table" then GamepadCameraOffsetDebugDB = {} end
    local debugStore = GamepadCameraOffsetDebugDB
    if type(debugStore.runs) ~= "table" then debugStore.runs = {} end
    return debugStore
end

local function copyCurrentSettings()
    local settings, copy = Camera.GetSettings(), {}
    for _, key in ipairs(SETTING_KEYS) do copy[key] = settings[key] end
    return copy
end

local function restoreSettings(savedCopy)
    local settings = Camera.GetSettings()
    for _, key in ipairs(SETTING_KEYS) do
        if savedCopy[key] ~= nil then settings[key] = savedCopy[key] end
    end
end

-- Checks

local currentRun   -- the run in progress, or nil

local function recordCheck(name, passed, expected, actual, note)
    local result = (passed == nil and "skip") or (passed and "pass") or "fail"
    currentRun.checks[#currentRun.checks + 1] = {
        name = name,
        result = result,
        expected = expected ~= nil and tostring(expected) or nil,
        actual = actual ~= nil and tostring(actual) or nil,
        note = note,
    }
end

local function expectEqual(name, expected, actual)
    recordCheck(name, tostring(actual) == tostring(expected), expected, actual)
end

local function expectNear(name, expected, actual, tolerance)
    local actualNumber = tonumber(actual)
    local passed = actualNumber ~= nil and math.abs(actualNumber - expected) <= (tolerance or 0.01)
    recordCheck(name, passed, expected, actual)
end

local function skipCheck(name, reason) recordCheck(name, nil, nil, nil, reason) end

local function changeSettings(newValues)
    local settings = Camera.GetSettings()
    for key, value in pairs(newValues) do settings[key] = value end
    Camera.Apply()
end

-- The steps, one every SECONDS_BETWEEN_STEPS.

local STEPS = {}
local function addStep(stepFunction) STEPS[#STEPS + 1] = stepFunction end

addStep(function()
    changeSettings({ enabled = true, side = 45, tilt = 50, keepOnScreen = false })
    expectEqual("settings page registered", true, Camera.category ~= nil)
    expectEqual("enabled: camera un-centered (CameraKeepCharacterCentered)", "0",
        Camera.GetCVar(Camera.CVAR_KEEP_CENTERED))
    expectEqual("enabled: CameraReduceUnexpectedMovement", "0", Camera.GetCVar(Camera.CVAR_REDUCE_MOVEMENT))
end)

for _, sidePercent in ipairs({ -100, -50, 0, 50, 100 }) do
    addStep(function()
        changeSettings({ side = sidePercent })
        local label = "side " .. Camera.Label(sidePercent, "Centered", "right", "left")
        expectNear(label .. ": test_cameraOverShoulder", sidePercent / 100 * Camera.SIDE_YARDS_AT_FULL,
            Camera.GetCVar(Camera.CVAR_OVER_SHOULDER))
    end)
end

addStep(function()
    changeSettings({ side = 100, keepOnScreen = true })
    expectNear("keep character on screen: side 100% right, limited by the zoom",
        math.min(Camera.SIDE_YARDS_AT_FULL, Camera.KeepOnScreen.MaxYards()), Camera.GetCVar(Camera.CVAR_OVER_SHOULDER))
    changeSettings({ keepOnScreen = false })
    expectNear("keep character on screen off: side 100% right, the full yards", Camera.SIDE_YARDS_AT_FULL,
        Camera.GetCVar(Camera.CVAR_OVER_SHOULDER))
end)

-- Tilt: off, then the pad expected for each percentage (0.75 at 1% down to
-- 0.125 at 100%, the game's pad working backwards).
local EXPECTED_TILT_PADS = { [1] = 0.75 - 0.625 / 100, [50] = 0.4375, [100] = 0.125 }
for _, tiltPercent in ipairs({ 0, 1, 50, 100 }) do
    addStep(function()
        changeSettings({ tilt = tiltPercent })
        local label = "tilt " .. Camera.Label(tiltPercent, "Off", "tilt")
        expectEqual(label .. ": test_cameraDynamicPitch", tiltPercent > 0 and "1" or "0",
            Camera.GetCVar(Camera.CVAR_DYNAMIC_PITCH))
        local expectedPad = EXPECTED_TILT_PADS[tiltPercent]
        if expectedPad then
            expectNear(label .. ": " .. Camera.CVAR_PITCH_PAD, expectedPad, Camera.GetCVar(Camera.CVAR_PITCH_PAD))
            expectNear(label .. ": " .. Camera.CVAR_PITCH_PAD_FLYING, expectedPad,
                Camera.GetCVar(Camera.CVAR_PITCH_PAD_FLYING))
        end
    end)
end

-- Tilt when looking down: the game's DownScale, the percentage as 0 to 1.
for _, lookDownPercent in ipairs({ 0, 50, 100 }) do
    addStep(function()
        changeSettings({ tilt = 50, lookDown = lookDownPercent })
        local label = "tilt when looking down " .. Camera.Label(lookDownPercent, "Default", "kept")
        local expected = lookDownPercent / 100
        if lookDownPercent == 0 then
            expected = tonumber(Camera.GetCVarDefault(Camera.CVAR_PITCH_DOWN_SCALE, "0.25")) or 0.25
        end
        expectNear(label .. ": " .. Camera.CVAR_PITCH_DOWN_SCALE, expected,
            Camera.GetCVar(Camera.CVAR_PITCH_DOWN_SCALE))
    end)
end

-- The game re-centering (as on a reload or a switch to the controller): the
-- addon should take the camera back on the next frame.
addStep(function()
    if C_CVar and C_CVar.SetTempCVar then pcall(C_CVar.SetTempCVar, Camera.CVAR_KEEP_CENTERED, "1") end
end)
addStep(function()
    expectEqual("game re-centers: taken back on the next frame", "0", Camera.GetCVar(Camera.CVAR_KEEP_CENTERED))
end)

addStep(function()
    changeSettings({ enabled = false })
    expectNear("disabled: test_cameraOverShoulder back to the game's default",
        tonumber(Camera.GetCVarDefault(Camera.CVAR_OVER_SHOULDER, "0")) or 0,
        Camera.GetCVar(Camera.CVAR_OVER_SHOULDER))
    expectNear("disabled: " .. Camera.CVAR_PITCH_PAD .. " back to the game's default",
        tonumber(Camera.GetCVarDefault(Camera.CVAR_PITCH_PAD, "0")) or 0,
        Camera.GetCVar(Camera.CVAR_PITCH_PAD))
    local name = "disabled: the controller's own centering back"
    if Camera.IsControllerUIOn() then
        expectEqual(name, "1", Camera.GetCVar(Camera.CVAR_KEEP_CENTERED))
    else
        skipCheck(name, "controller UI off")
    end
end)

addStep(function()
    changeSettings({ enabled = true })
    expectEqual("enabled again: camera un-centered", "0", Camera.GetCVar(Camera.CVAR_KEEP_CENTERED))
end)

-- The end: a reload writes the findings to disk. Addon code can't call
-- ReloadUI() on this client: the popup's Reload (Popup.lua) is a secure /reload
-- button; in a fight, the popup opens once it's over.
local function showReloadBox(text)
    Camera.Popup.Show({ text = text,
        buttons = { { text = RELOADUI or "Reload", reload = true }, { text = LATER or "Later" } } })
end

-- Results

local function countResults(run)
    local counts = { pass = 0, fail = 0, skip = 0 }
    for _, check in ipairs(run.checks) do counts[check.result] = counts[check.result] + 1 end
    return counts
end

function Debug.PrintRun(run)
    if not run then say("no saved run yet: /gpco debug"); return end
    local counts = countResults(run)
    local stoppedNote = run.stopped and (" (stopped: " .. run.stopped .. ")") or ""
    say(string.format("%s: %d passed, %d failed, %d skipped%s", run.time or "?",
        counts.pass, counts.fail, counts.skip, stoppedNote))
    for _, check in ipairs(run.checks) do
        if check.result == "fail" then
            say(string.format("|cffff5555FAIL|r %s: expected %s, got %s",
                check.name, check.expected or "?", check.actual or "nil"))
        end
    end
end

local function finishRun(stopReason)
    local run = currentRun
    currentRun = nil
    run.stopped = stopReason

    local debugStore = getDebugStore()
    if debugStore.settingsToRestore then
        restoreSettings(debugStore.settingsToRestore)
        debugStore.settingsToRestore = nil
    end
    Camera.Apply()

    local counts = countResults(run)
    run.passed, run.failed, run.skipped = counts.pass, counts.fail, counts.skip
    debugStore.runs[#debugStore.runs + 1] = run
    while #debugStore.runs > Debug.RUNS_KEPT do table.remove(debugStore.runs, 1) end

    Debug.PrintRun(run)
    say("your settings are back. /reload writes the findings to GamepadCameraOffsetDebugDB")
    showReloadBox(string.format("GamepadCameraOffset debug: %d passed, %d failed, %d skipped.\n"
        .. "Reload to save the findings (or type /reload).", counts.pass, counts.fail, counts.skip))
end

local function runNextStep()
    if not currentRun then return end
    currentRun.stepNumber = currentRun.stepNumber + 1
    local stepFunction = STEPS[currentRun.stepNumber]
    if not stepFunction then return finishRun() end
    local succeeded, errorMessage = pcall(stepFunction)
    if not succeeded then recordCheck("step " .. currentRun.stepNumber, false, "no error", errorMessage) end
    C_Timer.After(Debug.SECONDS_BETWEEN_STEPS, runNextStep)
end

local function describeEnvironment()
    local environment = {}
    if type(GetBuildInfo) == "function" then
        local succeeded, version, build, _, interfaceVersion = pcall(GetBuildInfo)
        if succeeded then
            environment.version, environment.build, environment.interfaceVersion = version, build, interfaceVersion
        end
    end
    environment.controllerUI = Camera.IsControllerUIOn()
    environment.zoom = type(GetCameraZoom) == "function" and tonumber(GetCameraZoom()) or nil
    environment.cameraFov = Camera.GetCVar("cameraFov")
    environment.screenHeight = UIParent:GetHeight()
    environment.uiScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or nil
    environment.settings = copyCurrentSettings()
    return environment
end

function Debug.Start()
    if currentRun then say("already running"); return end
    if InCombatLockdown() then say("not in combat"); return end
    getDebugStore().settingsToRestore = copyCurrentSettings()
    currentRun = {
        time = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or nil,
        environment = describeEnvironment(),
        checks = {},
        stepNumber = 0,
    }
    -- (No word about the game's experimental camera warning: the addon hides it.)
    say(string.format("running %d steps, about %d s. Don't touch the camera.", #STEPS,
        math.ceil(#STEPS * Debug.SECONDS_BETWEEN_STEPS)))
    runNextStep()
end

function Debug.Command(arguments)
    if arguments == "" or arguments == "run" then
        Debug.Start()
    elseif arguments == "last" then
        local runs = getDebugStore().runs
        Debug.PrintRun(runs[#runs])
    elseif arguments == "pad" and Camera.DebugPadProbe then
        Camera.DebugPadProbe.Start()
    elseif arguments == "side" and Camera.DebugSideProbe then
        Camera.DebugSideProbe.Start()
    elseif arguments == "worldframe" and Camera.DebugWorldFrameProbe then
        Camera.DebugWorldFrameProbe.Start()
    elseif arguments == "keys" and Camera.DebugKeys then
        Camera.DebugKeys.Toggle()
    elseif arguments == "clear" then
        getDebugStore().runs = {}
        say("saved runs cleared")
    else
        say("/gpco debug (run the suite), /gpco debug last, /gpco debug clear")
    end
end

Debug.eventFrame = CreateFrame("Frame")
Debug.eventFrame:RegisterEvent("PLAYER_LOGIN")
Debug.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
Debug.eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- A reload during a run left the test settings in: put yours back.
        local debugStore = getDebugStore()
        if debugStore.settingsToRestore then
            restoreSettings(debugStore.settingsToRestore)
            debugStore.settingsToRestore = nil
            say("a run was cut short: your settings are back")
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if currentRun then finishRun("combat") end
    end
end)
