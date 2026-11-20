-- GamepadCameraOffset: moves the camera sideways (over the shoulder) and up, keyboard or
-- controller. Settings sit in the game's Options > AddOns > Gamepad Camera Offset.
--
-- Why the controller needed more than the CVars: when the controller UI starts,
-- Blizzard_Gamepad/Core.lua (SetupCVarsForInputMode) puts
-- CameraKeepCharacterCentered = 1 on the game's TEMP CVar layer. A temp value
-- wins over the saved one, so SetCVar(..., 0) is written but never used, and a
-- centered camera ignores the offsets. Setting our own temp value of 0 wins
-- instead (checked in game with the DevCamOffset tool). The game sets its own
-- again on every reload and every switch to the controller, so this re-applies
-- whenever it sees CameraKeepCharacterCentered go back to 1.
--
-- The test_camera* CVars are the game's experimental camera: it clears them on
-- every reload (they're applied again at login). Before using them, the addon
-- turns on the game's ActionCam with the console command "ActionCam basic"
-- (once per session; the Only Cams addon does the same and says the CVars do
-- nothing until then; "basic", not "full", which drags the camera toward
-- targets). Turning GamepadCameraOffset off runs "ActionCam off".
--
-- The first change to one of them in a session makes the game show its
-- "experimental feature" warning (Blizzard_Game/Shared/EventImplementation.lua,
-- HandleExperimentalCVarConfirmationNeeded). Its Disable button clears them
-- all, so the addon stops the game listening for that event with
-- GameEvent.UnregisterInternalEvent, the game's own way to drop an event (as
-- SteadyCam does), and hides the warning if it shows up some other way.
local ADDON_NAME = ...

local Camera = {
    CVAR_OVER_SHOULDER = "test_cameraOverShoulder",
    CVAR_DYNAMIC_PITCH = "test_cameraDynamicPitch",
    CVAR_PITCH_PAD = "test_cameraDynamicPitchBaseFovPad",
    CVAR_PITCH_PAD_FLYING = "test_cameraDynamicPitchBaseFovPadFlying",
    CVAR_PITCH_DOWN_SCALE = "test_cameraDynamicPitchBaseFovPadDownScale",
    CVAR_KEEP_CENTERED = "CameraKeepCharacterCentered",
    CVAR_REDUCE_MOVEMENT = "CameraReduceUnexpectedMovement",
    -- What Blizzard's controller UI puts on the temp layer (Core.lua), put back on disable.
    CONTROLLER_TEMPORARY_VALUES = { CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0" },
    ACTION_CAMERA_ON_COMMAND = "ActionCam basic",
    ACTION_CAMERA_OFF_COMMAND = "ActionCam off",
    EXPERIMENTAL_WARNING_EVENT = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED",
    EXPERIMENTAL_WARNING_POPUP = "EXPERIMENTAL_CVAR_WARNING",

    -- Every slider is a percentage.
    --   side:   -100 (left shoulder) to 100 (right shoulder); 100% is SIDE_YARDS_AT_FULL.
    --   tilt:   0 (off) to 100 (strongest): tilts the camera up, so your character sits
    --           lower on the screen and you see more ahead. See Camera.TiltPad.
    --   lookDown: 1 to 100, how much of the tilt stays when you look down at your
    --           character (the game's DownScale, 0 to 1). 0 is Default: the game's
    --           own DownScale (0.25).
    DEFAULTS = { enabled = true, side = 40, tilt = 50, lookDown = 50 },
    SIDE_MIN = -100, SIDE_MAX = 100, SIDE_STEP = 5,
    TILT_MIN = 0, TILT_MAX = 100, TILT_STEP = 5,
    LOOK_DOWN_MIN = 0, LOOK_DOWN_MAX = 100, LOOK_DOWN_STEP = 5,
    SIDE_YARDS_AT_FULL = 3,       -- test_cameraOverShoulder at 100%
    -- The game's pitch pad works backwards: the lower it is, the more the camera
    -- tilts. Seen in game (DevCamOffset's tilt test, screenshots at 4, 15 and 39
    -- yd, 2026-11-19): 0.125 is the strongest usable tilt, by about 0.75 there's
    -- little left, and pad 0 is no tilt at all (so it's never sent). The tilt
    -- grows with the zoom: at 4 yd it barely shows, at 39 yd it's strongest.
    -- So 1% starts at 0.75 and 100% ends at 0.125.
    TILT_PAD_AT_LIGHTEST = 0.75,
    TILT_PAD_AT_STRONGEST = 0.125,

}
_G.GamepadCameraOffset = Camera

local cvarApi = C_CVar or {}

-- CVars

local function getCVar(name)
    local getter = cvarApi.GetCVar or GetCVar
    local succeeded, value = pcall(getter, name)
    return succeeded and value or nil
end

local function setCVar(name, value)
    local setter = cvarApi.SetCVar or SetCVar
    pcall(setter, name, tostring(value))
end

local function setTemporaryCVar(name, value)
    if type(cvarApi.SetTempCVar) == "function" then pcall(cvarApi.SetTempCVar, name, tostring(value)) end
end

local function removeTemporaryCVar(name)
    if type(cvarApi.RemoveTempCVar) == "function" then pcall(cvarApi.RemoveTempCVar, name) end
end

local function getCVarDefault(name, fallback)
    local getter = cvarApi.GetCVarDefault or GetCVarDefault
    if type(getter) ~= "function" then return fallback end
    local succeeded, value = pcall(getter, name)
    return succeeded and value or fallback
end

local function runConsoleCommand(command)
    if type(ConsoleExec) == "function" then pcall(ConsoleExec, command) end
end

local function isControllerUIOn()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function"
        and InputUtil.IsGamepadUIEnabled() == true
end

-- Saved settings

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, value))
end

local function getSettings()
    if type(GamepadCameraOffsetDB) ~= "table" then GamepadCameraOffsetDB = {} end
    local settings = GamepadCameraOffsetDB
    settings.crosshairColor = nil   -- 1.0's crosshair color: no longer part of this addon
    -- 1.6's "Crosshair on your target" is its own addon since 1.7.0: Gamepad Reticle On Target.
    if settings.crosshair ~= nil or settings.aim ~= nil then
        if settings.crosshair then Camera.reticleMoved = true end   -- said once, at login (RelatedAddon.lua)
        settings.crosshair, settings.aim, settings.nameplatesAsked = nil, nil, nil
    end
    for key, defaultValue in pairs(Camera.DEFAULTS) do
        if settings[key] == nil then settings[key] = defaultValue end
    end
    return settings
end

-- Applying and removing the offsets

-- The game's pitch pad for a tilt percentage, or nil for 0% (tilt off).
function Camera.TiltPad(tiltPercent)
    if tiltPercent <= 0 then return nil end
    local range = Camera.TILT_PAD_AT_LIGHTEST - Camera.TILT_PAD_AT_STRONGEST
    return Camera.TILT_PAD_AT_LIGHTEST - range * tiltPercent / 100
end

-- The game's experimental warning: stop the game listening for its event, and
-- hide the popup should it still be shown some other way. Done once.
local experimentalWarningSilenced = false
function Camera.SilenceExperimentalWarning()
    if experimentalWarningSilenced then return end
    experimentalWarningSilenced = true
    if type(GameEvent) == "table" and type(GameEvent.UnregisterInternalEvent) == "function" then
        pcall(GameEvent.UnregisterInternalEvent, Camera.EXPERIMENTAL_WARNING_EVENT)
    end
    if type(hooksecurefunc) == "function" and type(StaticPopup_Show) == "function" then
        hooksecurefunc("StaticPopup_Show", function(popupName)
            if popupName == Camera.EXPERIMENTAL_WARNING_POPUP and type(StaticPopup_Hide) == "function" then
                StaticPopup_Hide(popupName)
            end
        end)
    end
end

-- Whether GamepadCameraOffset's values are on the camera now (so disabling knows to undo them).
local offsetsApplied = false
-- Whether "ActionCam basic" ran since the addon last turned the camera on.
local actionCameraOn = false

function Camera.Apply()
    local settings = getSettings()
    if not settings.enabled then return Camera.Remove() end
    offsetsApplied = true
    if not actionCameraOn then
        actionCameraOn = true
        runConsoleCommand(Camera.ACTION_CAMERA_ON_COMMAND)   -- before our values: it sets some of its own
    end
    setTemporaryCVar(Camera.CVAR_KEEP_CENTERED, 0)
    setTemporaryCVar(Camera.CVAR_REDUCE_MOVEMENT, 0)

    local sidePercent = clamp(settings.side, Camera.SIDE_MIN, Camera.SIDE_MAX, Camera.DEFAULTS.side)
    setCVar(Camera.CVAR_OVER_SHOULDER, sidePercent / 100 * Camera.SIDE_YARDS_AT_FULL)

    local tiltPercent = clamp(settings.tilt, Camera.TILT_MIN, Camera.TILT_MAX, Camera.DEFAULTS.tilt)
    local pitchPad = Camera.TiltPad(tiltPercent)
    if pitchPad then
        setCVar(Camera.CVAR_DYNAMIC_PITCH, 1)
        setCVar(Camera.CVAR_PITCH_PAD, pitchPad)
        setCVar(Camera.CVAR_PITCH_PAD_FLYING, pitchPad)
        local lookDownPercent = clamp(settings.lookDown, Camera.LOOK_DOWN_MIN, Camera.LOOK_DOWN_MAX,
            Camera.DEFAULTS.lookDown)
        if lookDownPercent <= 0 then   -- Default: the game's own
            setCVar(Camera.CVAR_PITCH_DOWN_SCALE, getCVarDefault(Camera.CVAR_PITCH_DOWN_SCALE, "0.25"))
        else
            setCVar(Camera.CVAR_PITCH_DOWN_SCALE, lookDownPercent / 100)
        end
    else
        setCVar(Camera.CVAR_DYNAMIC_PITCH, 0)
    end
end

-- Puts the game's own values back: its defaults for the camera CVars, and on
-- the temp layer what the controller UI had there (nothing on keyboard).
function Camera.Remove()
    if not offsetsApplied then return end
    offsetsApplied = false
    if actionCameraOn then
        actionCameraOn = false
        runConsoleCommand(Camera.ACTION_CAMERA_OFF_COMMAND)
    end
    setCVar(Camera.CVAR_OVER_SHOULDER, getCVarDefault(Camera.CVAR_OVER_SHOULDER, "0"))
    setCVar(Camera.CVAR_DYNAMIC_PITCH, getCVarDefault(Camera.CVAR_DYNAMIC_PITCH, "0"))
    setCVar(Camera.CVAR_PITCH_PAD, getCVarDefault(Camera.CVAR_PITCH_PAD, "0"))
    setCVar(Camera.CVAR_PITCH_PAD_FLYING, getCVarDefault(Camera.CVAR_PITCH_PAD_FLYING, "0"))
    setCVar(Camera.CVAR_PITCH_DOWN_SCALE, getCVarDefault(Camera.CVAR_PITCH_DOWN_SCALE, "0"))
    for name, controllerValue in pairs(Camera.CONTROLLER_TEMPORARY_VALUES) do
        if isControllerUIOn() then setTemporaryCVar(name, controllerValue) else removeTemporaryCVar(name) end
    end
end

-- Apply on the next frame, once, however many reasons came in this frame.
local applyQueued = false
function Camera.ApplyNextFrame()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0, function()
        applyQueued = false
        Camera.Apply()
    end)
end

-- For Debug.lua (/gco debug), which checks what these actually did.
Camera.GetSettings = getSettings
Camera.GetCVar = getCVar
Camera.GetCVarDefault = getCVarDefault
Camera.IsControllerUIOn = isControllerUIOn

-- Settings: Options > AddOns > Gamepad Camera Offset

-- A slider's label: zero as a word ("Centered", "Default"), the rest as a whole
-- percentage with a direction ("40% right").
function Camera.Label(value, zeroWord, positiveWord, negativeWord)
    local number = tonumber(value) or 0
    local amount = math.floor(math.abs(number) + 0.5)
    if amount == 0 then return zeroWord end
    local direction = (number < 0 and negativeWord) or positiveWord
    return string.format("%d%% %s", amount, direction)
end

local function sliderOptions(minimum, maximum, step, formatLabel)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    local rightLabel = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        and MinimalSliderWithSteppersMixin.Label.Right
    if rightLabel and options.SetLabelFormatter then options:SetLabelFormatter(rightLabel, formatLabel) end
    return options
end

function Camera.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local settings = getSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Gamepad Camera Offset")
    Camera.category = category

    local function addSetting(key, valueType, label, tooltip, options)
        local variableName = "GamepadCameraOffset_" .. key
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, settings, valueType, label,
            Camera.DEFAULTS[key])
        Settings.SetOnValueChangedCallback(variableName, function() Camera.Apply() end)
        if valueType == Settings.VarType.Boolean then
            Settings.CreateCheckbox(category, setting, tooltip)
        else
            Settings.CreateSlider(category, setting, options, tooltip)
        end
    end

    addSetting("enabled", Settings.VarType.Boolean, "Enable",
        "Moves the camera with the settings below, on keyboard and on a controller.\n\n"
        .. "Turned off, the game's own camera comes back.\n\n"
        .. "These are the game's experimental camera settings (its ActionCam); "
        .. "the game's warning about them is hidden.")
    addSetting("side", Settings.VarType.Number, "Side offset",
        "Moves the camera over your right or left shoulder.\n\n"
        .. "• Centered: the game's normal view\n"
        .. "• 100%: the furthest it goes\n\n"
        .. "The effect is stronger when you zoom in.",
        sliderOptions(Camera.SIDE_MIN, Camera.SIDE_MAX, Camera.SIDE_STEP,
            function(value) return Camera.Label(value, "Centered", "right", "left") end))
    addSetting("tilt", Settings.VarType.Number, "Tilt",
        "Tilts the camera up, so:\n"
        .. "• Your character sits lower on the screen\n"
        .. "• You see more ahead\n\n"
        .. "• Off: the game's own view\n"
        .. "• 100%: the strongest tilt\n\n"
        .. "The further you zoom out, the stronger it is; close up it barely shows.",
        sliderOptions(Camera.TILT_MIN, Camera.TILT_MAX, Camera.TILT_STEP,
            function(value) return Camera.Label(value, "Off", "tilt") end))
    addSetting("lookDown", Settings.VarType.Number, "Tilt when looking down",
        "How much of the tilt stays when you look down at your character.\n\n"
        .. "• Default: the game's own (about 25%)\n"
        .. "• Lower: it fades more as you look down\n"
        .. "• 100%: as strong as with a level camera\n\n"
        .. "Only used while Tilt is on.",
        sliderOptions(Camera.LOOK_DOWN_MIN, Camera.LOOK_DOWN_MAX, Camera.LOOK_DOWN_STEP,
            function(value) return Camera.Label(value, "Default", "kept") end))
    if Camera.AddRelatedAddonButton then Camera.AddRelatedAddonButton(layout) end   -- RelatedAddon.lua
    Settings.RegisterAddOnCategory(category)
end

function Camera.Open()
    if Camera.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(Camera.category:GetID())
    end
end

-- Events

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CVAR_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        getSettings()
        Camera.SilenceExperimentalWarning()
        pcall(Camera.RegisterSettings)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The controller UI sets its temp values around now too: apply after it.
        Camera.ApplyNextFrame()
    elseif event == "CVAR_UPDATE" then
        -- The game took the camera back (a reload, a switch to the controller).
        local isCenteringCVar = type(name) == "string" and name:lower() == Camera.CVAR_KEEP_CENTERED:lower()
        if isCenteringCVar and getSettings().enabled and getCVar(Camera.CVAR_KEEP_CENTERED) ~= "0" then
            Camera.ApplyNextFrame()
        end
    end
end)

-- /gco (or /gamepadcameraoffset) opens the settings; /gco debug ... goes to the debug suite (Debug.lua).
SLASH_GAMEPADCAMERAOFFSET1 = "/gco"
SLASH_GAMEPADCAMERAOFFSET2 = "/gamepadcameraoffset"
SlashCmdList.GAMEPADCAMERAOFFSET = function(message)
    local command, arguments = tostring(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" and Camera.Debug then return Camera.Debug.Command(arguments) end
    Camera.Open()
end
