-- GamepadCameraOffset: moves the camera sideways (over the shoulder) and up, keyboard or
-- controller. Settings sit in the game's Options > AddOns > GamepadCameraOffset.
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
-- every reload (they're applied again at login), and the first change in a
-- session shows the game's "experimental feature" warning. Its Disable button
-- clears them again; GamepadCameraOffset leaves them cleared until you change a setting
-- or reload.
local ADDON_NAME = ...

local Camera = {
    CVAR_OVER_SHOULDER = "test_cameraOverShoulder",
    CVAR_DYNAMIC_PITCH = "test_cameraDynamicPitch",
    CVAR_PITCH_PAD = "test_cameraDynamicPitchBaseFovPad",
    CVAR_PITCH_PAD_FLYING = "test_cameraDynamicPitchBaseFovPadFlying",
    CVAR_KEEP_CENTERED = "CameraKeepCharacterCentered",
    CVAR_REDUCE_MOVEMENT = "CameraReduceUnexpectedMovement",
    -- What Blizzard's controller UI puts on the temp layer (Core.lua), put back on disable.
    CONTROLLER_TEMPORARY_VALUES = { CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0" },

    -- Every slider is a percentage.
    --   side:   -100 (left shoulder) to 100 (right shoulder); 100% is SIDE_YARDS_AT_FULL.
    --   height: 0 to 100; 100% is HEIGHT_PAD_AT_FULL of the view kept above the character.
    --   aim:    -25 (down) to 25 (up), in percent of the screen's height.
    DEFAULTS = { enabled = true, side = 40, height = 35, crosshair = true, aim = 0 },
    SIDE_MIN = -100, SIDE_MAX = 100, SIDE_STEP = 5,
    HEIGHT_MIN = 0, HEIGHT_MAX = 100, HEIGHT_STEP = 5,
    AIM_MIN = -25, AIM_MAX = 25, AIM_STEP = 1,
    SIDE_YARDS_AT_FULL = 3,       -- test_cameraOverShoulder at 100%
    HEIGHT_PAD_AT_FULL = 0.9,     -- test_cameraDynamicPitchBaseFovPad at 100%

    -- Where the character sits on screen. The camera aims at the character, then
    -- slides sideways by the shoulder offset, so the character sits that many
    -- yards left of the middle, seen from the zoom distance. At cameraFov 90 the
    -- view is 90 degrees across a 4:3 screen, so tan(half its height) is 3/4 of
    -- tan(half the field of view).
    DEFAULT_FIELD_OF_VIEW = 90,        -- cameraFov when the CVar can't be read
    SCREEN_HEIGHT_TO_WIDTH = 0.75,     -- 4:3: the height's share of the width
    MINIMUM_ZOOM_YARDS = 1.5,          -- closer counts as this (first person)
    CROSSHAIR_MOVE_THRESHOLD = 0.5,    -- UI units the crosshair must move before it's placed again
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
    for key, defaultValue in pairs(Camera.DEFAULTS) do
        if settings[key] == nil then settings[key] = defaultValue end
    end
    return settings
end

-- Applying and removing the offsets

-- Whether GamepadCameraOffset's values are on the camera now (so disabling knows to undo them).
local offsetsApplied = false

function Camera.Apply()
    local settings = getSettings()
    if not settings.enabled then return Camera.Remove() end
    offsetsApplied = true
    setTemporaryCVar(Camera.CVAR_KEEP_CENTERED, 0)
    setTemporaryCVar(Camera.CVAR_REDUCE_MOVEMENT, 0)

    local sidePercent = clamp(settings.side, Camera.SIDE_MIN, Camera.SIDE_MAX, Camera.DEFAULTS.side)
    setCVar(Camera.CVAR_OVER_SHOULDER, sidePercent / 100 * Camera.SIDE_YARDS_AT_FULL)

    local heightPercent = clamp(settings.height, Camera.HEIGHT_MIN, Camera.HEIGHT_MAX, Camera.DEFAULTS.height)
    local pitchPad = heightPercent / 100 * Camera.HEIGHT_PAD_AT_FULL
    setCVar(Camera.CVAR_DYNAMIC_PITCH, pitchPad > 0 and 1 or 0)
    setCVar(Camera.CVAR_PITCH_PAD, pitchPad)
    setCVar(Camera.CVAR_PITCH_PAD_FLYING, pitchPad)

    Camera.WatchCrosshair()
end

-- Puts the game's own values back: its defaults for the camera CVars, and on
-- the temp layer what the controller UI had there (nothing on keyboard).
function Camera.Remove()
    if not offsetsApplied then return Camera.WatchCrosshair() end
    offsetsApplied = false
    setCVar(Camera.CVAR_OVER_SHOULDER, getCVarDefault(Camera.CVAR_OVER_SHOULDER, "0"))
    setCVar(Camera.CVAR_DYNAMIC_PITCH, getCVarDefault(Camera.CVAR_DYNAMIC_PITCH, "0"))
    setCVar(Camera.CVAR_PITCH_PAD, getCVarDefault(Camera.CVAR_PITCH_PAD, "0"))
    setCVar(Camera.CVAR_PITCH_PAD_FLYING, getCVarDefault(Camera.CVAR_PITCH_PAD_FLYING, "0"))
    for name, controllerValue in pairs(Camera.CONTROLLER_TEMPORARY_VALUES) do
        if isControllerUIOn() then setTemporaryCVar(name, controllerValue) else removeTemporaryCVar(name) end
    end
    Camera.WatchCrosshair()
end

-- The crosshair: the controller UI's GamepadReticle, a small dot Blizzard puts
-- at the screen's middle (x) and the engine's aim height (GetCursorCenterPosition).
-- It's a plain frame, not a protected one, so it moves in combat too. Blizzard
-- puts it back on a resize (GamepadReticleMixin:Recenter), which is hooked.
-- Moving it only moves the dot: what the controller's soft targeting picks is
-- decided by the game, not by the dot.

-- Secret values (hidden from addons in some situations) can't be used in math.
local function readableOrNil(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local function getCVarNumber(name)
    return tonumber(readableOrNil(getCVar(name)))
end

-- The character's offset from the screen's middle, in UIParent units (x only:
-- the height setting tilts the camera around the character, which stays on
-- the middle line).
function Camera.CharacterX()
    local shoulderYards = getCVarNumber(Camera.CVAR_OVER_SHOULDER) or 0
    if shoulderYards == 0 then return 0 end
    local zoom = type(GetCameraZoom) == "function" and tonumber(readableOrNil(GetCameraZoom())) or nil
    if not zoom then return nil end
    local fieldOfView = getCVarNumber("cameraFov") or Camera.DEFAULT_FIELD_OF_VIEW
    if fieldOfView <= 0 then fieldOfView = Camera.DEFAULT_FIELD_OF_VIEW end
    local tangentOfHalfHeight = Camera.SCREEN_HEIGHT_TO_WIDTH * math.tan(math.rad(fieldOfView) / 2)
    local distance = math.max(zoom, Camera.MINIMUM_ZOOM_YARDS)
    local unitsPerYard = UIParent:GetHeight() / (2 * distance * tangentOfHalfHeight)
    return -shoulderYards * unitsPerYard
end

local lastCrosshairPosition   -- { x, y } where it was last put, or nil when Blizzard placed it

local function shouldMoveCrosshair()
    local settings = getSettings()
    return settings.enabled and settings.crosshair and isControllerUIOn() and type(GamepadReticle) == "table"
end

-- The height the game aims at, in the crosshair frame's units.
local function getAimHeight(crosshairFrame)
    local scale = crosshairFrame:GetEffectiveScale()
    if type(GetCursorCenterPosition) ~= "function" or not scale or scale <= 0 then return nil end
    local _, aimY = GetCursorCenterPosition()
    aimY = tonumber(readableOrNil(aimY))
    return aimY and aimY / scale or nil
end

function Camera.PlaceCrosshair(forced)
    local crosshairFrame = _G.GamepadReticle
    if not shouldMoveCrosshair() then
        if lastCrosshairPosition and type(crosshairFrame) == "table" then
            lastCrosshairPosition = nil
            if type(crosshairFrame.Recenter) == "function" then crosshairFrame:Recenter() end
        end
        return
    end
    local x, y = Camera.CharacterX(), getAimHeight(crosshairFrame)
    if not x or not y then return end
    local aimPercent = clamp(getSettings().aim, Camera.AIM_MIN, Camera.AIM_MAX, 0)
    y = y + aimPercent / 100 * UIParent:GetHeight()
    local last = lastCrosshairPosition
    local barelyMoved = last and math.abs(last.x - x) < Camera.CROSSHAIR_MOVE_THRESHOLD
        and math.abs(last.y - y) < Camera.CROSSHAIR_MOVE_THRESHOLD
    if barelyMoved and not forced then return end
    lastCrosshairPosition = { x = x, y = y }
    crosshairFrame:ClearAllPoints()
    crosshairFrame:SetPoint("CENTER", UIParent, "BOTTOM", x, y)
end

-- Follows the zoom every frame while the crosshair is on (placing it only when
-- it moved), and takes it back after Blizzard's own Recenter.
local crosshairFollower = CreateFrame("Frame")
crosshairFollower:Hide()   -- shown by WatchCrosshair, once the saved settings are in
crosshairFollower:SetScript("OnUpdate", function(self)
    Camera.PlaceCrosshair()
    if not shouldMoveCrosshair() then self:Hide() end
end)

local recenterHooked = false
function Camera.WatchCrosshair()
    local crosshairFrame = _G.GamepadReticle
    local canHook = type(crosshairFrame) == "table" and type(crosshairFrame.Recenter) == "function"
        and type(hooksecurefunc) == "function"
    if not recenterHooked and canHook then
        recenterHooked = true
        hooksecurefunc(crosshairFrame, "Recenter", function()
            if shouldMoveCrosshair() then Camera.PlaceCrosshair(true) else lastCrosshairPosition = nil end
        end)
    end
    if shouldMoveCrosshair() then crosshairFollower:Show() else crosshairFollower:Hide() end
    Camera.PlaceCrosshair(true)
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
Camera.GetAimHeight = getAimHeight

-- Settings: Options > AddOns > GamepadCameraOffset

-- A slider's label: zero as a word ("Centered", "Normal"), the rest as a whole
-- percentage with a direction ("40% right", "10% down").
function Camera.Label(value, zeroWord, positiveWord, negativeWord)
    local number = tonumber(value) or 0
    local percent = math.floor(math.abs(number) + 0.5)
    if percent == 0 then return zeroWord end
    local direction = (number < 0 and negativeWord) or positiveWord
    return string.format("%d%% %s", percent, direction)
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
    local category = Settings.RegisterVerticalLayoutCategory("GamepadCameraOffset")
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
        "Moves the camera with the settings below, on keyboard and on a controller. "
        .. "Turned off, the game's own camera comes back.\n\n"
        .. "These are the game's experimental camera settings: the first change in a "
        .. "session shows its warning. Accept keeps them.")
    addSetting("side", Settings.VarType.Number, "Side offset",
        "Moves the camera over your right or left shoulder. Centered is the game's normal view; "
        .. "100% is the furthest the addon goes. The effect is stronger when you zoom in.",
        sliderOptions(Camera.SIDE_MIN, Camera.SIDE_MAX, Camera.SIDE_STEP,
            function(value) return Camera.Label(value, "Centered", "right", "left") end))
    addSetting("height", Settings.VarType.Number, "Height",
        "Raises the camera's view so your character sits lower on the screen. Normal is the game's "
        .. "own view; 100% is the furthest the addon goes. The effect is stronger when you zoom out.",
        sliderOptions(Camera.HEIGHT_MIN, Camera.HEIGHT_MAX, Camera.HEIGHT_STEP,
            function(value) return Camera.Label(value, "Normal", "higher") end))
    addSetting("crosshair", Settings.VarType.Boolean, "Crosshair follows your character",
        "With the controller UI on, moves its aiming dot sideways so it stays in line with "
        .. "your character as the side offset and your zoom change. Only the dot moves: "
        .. "what the controller targets is still decided by the game.")
    addSetting("aim", Settings.VarType.Number, "Crosshair height",
        "Moves the controller's aiming dot up or down from where the game puts it, "
        .. "in percent of the screen's height. Normal is the game's own place.",
        sliderOptions(Camera.AIM_MIN, Camera.AIM_MAX, Camera.AIM_STEP,
            function(value) return Camera.Label(value, "Normal", "up", "down") end))

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

-- /gco opens the settings; /gco debug ... goes to the debug suite (Debug.lua).
SLASH_GAMEPADCAMERAOFFSET1 = "/gco"
SlashCmdList.GAMEPADCAMERAOFFSET = function(message)
    local command, arguments = tostring(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" and Camera.Debug then return Camera.Debug.Command(arguments) end
    Camera.Open()
end
