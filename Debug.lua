-- /gco debug: an in-game test suite. It runs through the settings one step at a
-- time (a step every Debug.SECONDS_BETWEEN_STEPS, so you can watch the camera
-- move), checks what the game actually took (the CVars, the crosshair's place),
-- puts your own settings back, and keeps the findings in
-- GamepadCameraOffsetDebugDB, which the game writes to disk on /reload or logout.
--   /gco debug         runs the suite (out of combat)
--   /gco debug last    prints the last run's findings again
--   /gco debug clear   empties the saved runs
-- A fight stops the run (and puts your settings back). If a reload cuts a run
-- short, your settings are put back at the next login.

local Camera = _G.GamepadCameraOffset
local Debug = { SECONDS_BETWEEN_STEPS = 0.6, RUNS_KEPT = 10 }
Camera.Debug = Debug

local SETTING_KEYS = { "enabled", "side", "tilt", "crosshair", "aim" }

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

local function canCheckCrosshair()
    return Camera.IsControllerUIOn() and type(_G.GamepadReticle) == "table"
        and type(GamepadReticle.GetPoint) == "function"
end

local function getCrosshairPosition()
    local succeeded, _, _, _, x, y = pcall(GamepadReticle.GetPoint, GamepadReticle, 1)
    if succeeded then return x, y end
end

local function checkCrosshair(label, aimPercent)
    local name = "crosshair at " .. label
    if not canCheckCrosshair() then return skipCheck(name, "controller UI off") end
    local expectedX, aimHeight = Camera.CharacterX(), Camera.GetAimHeight(GamepadReticle)
    if not expectedX or not aimHeight then
        return skipCheck(name, "zoom or the game's aim height can't be read")
    end
    local x, y = getCrosshairPosition()
    expectNear(name .. ": x, in line with the character", expectedX, x, 1)
    expectNear(name .. ": y", aimHeight + aimPercent / 100 * UIParent:GetHeight(), y, 1)
end

-- The steps, one every SECONDS_BETWEEN_STEPS.

local STEPS = {}
local function addStep(stepFunction) STEPS[#STEPS + 1] = stepFunction end

addStep(function()
    changeSettings({ enabled = true, side = 45, tilt = 50, crosshair = true, aim = 0 })
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
        checkCrosshair(label, 0)
    end)
end

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

for _, aimPercent in ipairs({ 10, -10, 0 }) do
    addStep(function()
        changeSettings({ side = 50, aim = aimPercent })
        checkCrosshair("crosshair height " .. Camera.Label(aimPercent, "Normal", "up", "down"), aimPercent)
    end)
end

addStep(function()
    changeSettings({ crosshair = false })
    if not canCheckCrosshair() then return skipCheck("crosshair off", "controller UI off") end
    local x = getCrosshairPosition()
    expectNear("crosshair off: back in the middle, where the game puts it", 0, x, 1)
end)

-- The game re-centering (as on a reload or a switch to the controller): the
-- addon should take the camera back on the next frame.
addStep(function()
    changeSettings({ crosshair = true })
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
-- ReloadUI() on this client, so the box's Reload is a secure /reload button.

local reloadBox
local function showReloadBox(text)
    if InCombatLockdown() then
        -- A box holding a secure button can't be shown in combat: wait for the end.
        Debug.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        Debug.reloadBoxTextAfterCombat = text
        return
    end
    if not reloadBox then
        reloadBox = CreateFrame("Frame", "GamepadCameraOffsetDebugBox", UIParent)
        reloadBox:SetSize(340, 110)
        reloadBox:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        reloadBox:SetFrameStrata("DIALOG")
        local background = reloadBox:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.85)
        reloadBox.text = reloadBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        reloadBox.text:SetPoint("TOP", reloadBox, "TOP", 0, -14)
        reloadBox.text:SetWidth(310)

        local reloadButton = CreateFrame("Button", "GamepadCameraOffsetDebugReload", reloadBox,
            "SecureActionButtonTemplate,UIPanelButtonTemplate")
        reloadButton:SetAttribute("type", "macro")
        reloadButton:SetAttribute("macrotext", "/reload")
        reloadButton:RegisterForClicks("AnyUp", "AnyDown")
        reloadButton:SetSize(130, 24)
        reloadButton:SetPoint("BOTTOMLEFT", reloadBox, "BOTTOMLEFT", 30, 14)
        reloadButton:SetText(RELOADUI or "Reload")

        local laterButton = CreateFrame("Button", nil, reloadBox, "UIPanelButtonTemplate")
        laterButton:SetSize(130, 24)
        laterButton:SetPoint("BOTTOMRIGHT", reloadBox, "BOTTOMRIGHT", -30, 14)
        laterButton:SetText(LATER or "Later")
        laterButton:SetScript("OnClick", function() reloadBox:Hide() end)

        reloadBox.reloadButton, reloadBox.laterButton = reloadButton, laterButton
    end
    reloadBox.text:SetText(text)
    reloadBox:Show()
    Debug.reloadBox = reloadBox
end

-- Results

local function countResults(run)
    local counts = { pass = 0, fail = 0, skip = 0 }
    for _, check in ipairs(run.checks) do counts[check.result] = counts[check.result] + 1 end
    return counts
end

function Debug.PrintRun(run)
    if not run then say("no saved run yet: /gco debug"); return end
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
    environment.crosshairFound = type(_G.GamepadReticle) == "table"
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
    say(string.format("running %d steps, about %d s. Don't touch the camera; accept the game's "
        .. "experimental camera warning if it shows.", #STEPS, math.ceil(#STEPS * Debug.SECONDS_BETWEEN_STEPS)))
    runNextStep()
end

function Debug.Command(arguments)
    if arguments == "" or arguments == "run" then
        Debug.Start()
    elseif arguments == "last" then
        local runs = getDebugStore().runs
        Debug.PrintRun(runs[#runs])
    elseif arguments == "clear" then
        getDebugStore().runs = {}
        say("saved runs cleared")
    else
        say("/gco debug (run the suite), /gco debug last, /gco debug clear")
    end
end

Debug.eventFrame = CreateFrame("Frame")
Debug.eventFrame:RegisterEvent("PLAYER_LOGIN")
Debug.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
Debug.eventFrame:SetScript("OnEvent", function(self, event)
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
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local text = Debug.reloadBoxTextAfterCombat
        if text then
            Debug.reloadBoxTextAfterCombat = nil
            showReloadBox(text)
        end
    end
end)
