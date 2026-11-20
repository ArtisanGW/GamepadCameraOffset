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
    --   aim:    the crosshair's vertical offset on a target: -200 (down) to 200 (up)
    --           screen pixels from just below its nameplate. Pixels, not a percentage:
    --           a nameplate keeps its size on screen at any distance, so a pixel
    --           offset puts the dot at the same place on it.
    DEFAULTS = { enabled = true, side = 40, tilt = 50, lookDown = 50, crosshair = true, aim = 0 },
    SIDE_MIN = -100, SIDE_MAX = 100, SIDE_STEP = 5,
    TILT_MIN = 0, TILT_MAX = 100, TILT_STEP = 5,
    LOOK_DOWN_MIN = 0, LOOK_DOWN_MAX = 100, LOOK_DOWN_STEP = 5,
    AIM_MIN = -200, AIM_MAX = 200, AIM_STEP = 5,
    SIDE_YARDS_AT_FULL = 3,       -- test_cameraOverShoulder at 100%
    -- The game's pitch pad works backwards: the lower it is, the more the camera
    -- tilts. Seen in game (DevCamOffset's tilt test, screenshots at 4, 15 and 39
    -- yd, 2026-11-19): 0.125 is the strongest usable tilt, by about 0.75 there's
    -- little left, and pad 0 is no tilt at all (so it's never sent). The tilt
    -- grows with the zoom: at 4 yd it barely shows, at 39 yd it's strongest.
    -- So 1% starts at 0.75 and 100% ends at 0.125.
    TILT_PAD_AT_LIGHTEST = 0.75,
    TILT_PAD_AT_STRONGEST = 0.125,

    -- The crosshair on a target: this far below its nameplate, in UI units.
    CROSSHAIR_BELOW_NAMEPLATE = 12,
    -- Whose nameplate the crosshair goes on: your target, friendly or not, or with
    -- no target the controller's soft target (what it would attack). With a target
    -- selected it never jumps to another unit: no nameplate for it (friendly ones
    -- are off unless the game's friendly nameplates are on), and it stays where
    -- the game aims.
    CROSSHAIR_TARGET_UNITS = { "target", "softenemy" },
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

    Camera.WatchCrosshair()
end

-- Puts the game's own values back: its defaults for the camera CVars, and on
-- the temp layer what the controller UI had there (nothing on keyboard).
function Camera.Remove()
    if not offsetsApplied then return Camera.WatchCrosshair() end
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
    Camera.WatchCrosshair()
end

-- The crosshair: the controller UI's GamepadReticle, a small dot Blizzard puts
-- at the screen's middle (x) and the engine's aim height (GetCursorCenterPosition):
-- where the controller's automatic targeting aims. It also holds the auto-attack
-- swing timer, so it stays. Blizzard places it once and again only on a resize
-- (GamepadReticleMixin:Recenter in Blizzard_Gamepad/UI/Reticle/GamepadReticle.lua).
--
-- With a target (yours, or else the controller's soft target), the dot goes just
-- below the target's nameplate: anchored to it, so the game moves it with the
-- target and nothing here runs per frame. It's placed again only when the target
-- changes or its nameplate comes or goes. With no target, or no nameplate (they're
-- off, or the target is off screen), it stays where the game aims. The crosshair
-- vertical offset setting moves it up or down from the nameplate. (Following the character instead, as
-- before, put the dot far from what you were attacking: seen in game.)
-- It's a plain frame, not a protected one, so it moves in combat too.

-- Secret values (hidden from addons in some situations) can't be used in math.
local function readableOrNil(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local crosshairPlacedOn   -- "nameplate", "screen", or nil while Blizzard placed it
local crosshairPlacement  -- on a nameplate: { anchor = the part it's under, height = its offset }

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

-- Screen pixels as a frame's own units: the screen is 768 units tall at an
-- effective scale of 1, whatever its pixels (GetPhysicalScreenSize).
Camera.SCREEN_HEIGHT_IN_UNITS = 768
function Camera.PixelsToFrameUnits(frame, pixels)
    local scale = frame:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    local physicalHeight
    if type(GetPhysicalScreenSize) == "function" then
        local _, height = GetPhysicalScreenSize()
        physicalHeight = tonumber(readableOrNil(height))
    end
    if not physicalHeight or physicalHeight <= 0 then physicalHeight = Camera.SCREEN_HEIGHT_IN_UNITS end
    return pixels * Camera.SCREEN_HEIGHT_IN_UNITS / physicalHeight / scale
end

-- The part of a nameplate you see: its health bar, or with names only (friendly
-- players, as an option) its name, else the whole plate. The plate keeps its
-- full size either way, so its own bottom can sit well below a name.
function Camera.VisibleNameplatePart(nameplate)
    local unitFrame = nameplate.UnitFrame
    if type(unitFrame) == "table" then
        for _, part in ipairs({ unitFrame.healthBar, unitFrame.name }) do
            if type(part) == "table" and type(part.IsVisible) == "function" and part:IsVisible() then return part end
        end
    end
    return nameplate
end

-- The crosshair's unit: the first of CROSSHAIR_TARGET_UNITS that exists. Then its
-- nameplate, if it has one, and the unit.
function Camera.CrosshairTargetNameplate()
    local namePlates = _G.C_NamePlate
    if type(namePlates) ~= "table" or type(namePlates.GetNamePlateForUnit) ~= "function" then return nil end
    if type(UnitExists) ~= "function" then return nil end
    for _, unit in ipairs(Camera.CROSSHAIR_TARGET_UNITS) do
        if UnitExists(unit) then
            local succeeded, nameplate = pcall(namePlates.GetNamePlateForUnit, unit)
            if succeeded and nameplate then return nameplate, unit end
            return nil, unit
        end
    end
    return nil
end

function Camera.PlaceCrosshair()
    local crosshairFrame = _G.GamepadReticle
    if not shouldMoveCrosshair() then
        if crosshairPlacedOn and type(crosshairFrame) == "table" then
            crosshairPlacedOn = nil
            if type(crosshairFrame.Recenter) == "function" then crosshairFrame:Recenter() end
        end
        return
    end
    local nameplate = Camera.CrosshairTargetNameplate()
    if nameplate then
        local anchor = Camera.VisibleNameplatePart(nameplate)
        local offsetPixels = clamp(getSettings().aim, Camera.AIM_MIN, Camera.AIM_MAX, 0)
        local heightFromNameplate = -Camera.CROSSHAIR_BELOW_NAMEPLATE + Camera.PixelsToFrameUnits(crosshairFrame, offsetPixels)
        crosshairFrame:ClearAllPoints()
        crosshairFrame:SetPoint("CENTER", anchor, "BOTTOM", 0, heightFromNameplate)
        crosshairPlacedOn = "nameplate"
        crosshairPlacement = { anchor = anchor, height = heightFromNameplate }
        return
    end
    local aimHeight = getAimHeight(crosshairFrame)
    if not aimHeight then return end
    crosshairFrame:ClearAllPoints()
    crosshairFrame:SetPoint("CENTER", UIParent, "BOTTOM", 0, aimHeight)
    crosshairPlacedOn = "screen"
end
Camera.CrosshairPlacedOn = function() return crosshairPlacedOn end
-- Where it was put on a nameplate: { anchor, height }. Asked here, not measured:
-- a frame anchored to a nameplate (a restricted region) can't be measured from
-- addon code (GetPoint fails: "Can't measure restricted regions", seen in game).
Camera.CrosshairPlacement = function() return crosshairPlacedOn == "nameplate" and crosshairPlacement or nil end

-- Placed again on the next frame, once, however many reasons came in this frame
-- (a nameplate going away is still on its unit while its event runs).
local crosshairPlaceQueued = false
local function placeCrosshairNextFrame()
    if crosshairPlaceQueued then return end
    crosshairPlaceQueued = true
    C_Timer.After(0, function()
        crosshairPlaceQueued = false
        Camera.PlaceCrosshair()
    end)
end

local CROSSHAIR_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED" }
local crosshairEventFrame = CreateFrame("Frame")
crosshairEventFrame:SetScript("OnEvent", function() placeCrosshairNextFrame() end)

local recenterHooked = false
function Camera.WatchCrosshair()
    local crosshairFrame = _G.GamepadReticle
    local canHook = type(crosshairFrame) == "table" and type(crosshairFrame.Recenter) == "function"
        and type(hooksecurefunc) == "function"
    if not recenterHooked and canHook then
        recenterHooked = true
        -- Blizzard's own Recenter (a resize) puts it back in the middle: ours after it.
        hooksecurefunc(crosshairFrame, "Recenter", function()
            if shouldMoveCrosshair() then Camera.PlaceCrosshair() else crosshairPlacedOn = nil end
        end)
    end
    for _, event in ipairs(CROSSHAIR_EVENTS) do
        if shouldMoveCrosshair() then pcall(crosshairEventFrame.RegisterEvent, crosshairEventFrame, event)
        else crosshairEventFrame:UnregisterEvent(event) end
    end
    Camera.PlaceCrosshair()
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

-- Settings: Options > AddOns > Gamepad Camera Offset

-- A slider's label: zero as a word ("Centered", "Default"), the rest as a whole
-- percentage with a direction ("40% right"), or in a unit when given ("20 px down").
function Camera.Label(value, zeroWord, positiveWord, negativeWord, unit)
    local number = tonumber(value) or 0
    local amount = math.floor(math.abs(number) + 0.5)
    if amount == 0 then return zeroWord end
    local direction = (number < 0 and negativeWord) or positiveWord
    if unit then return string.format("%d %s %s", amount, unit, direction) end
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
        "Moves the camera with the settings below, on keyboard and on a controller. "
        .. "Turned off, the game's own camera comes back.\n\n"
        .. "These are the game's experimental camera settings (its ActionCam). "
        .. "The game's warning about them is hidden.")
    addSetting("side", Settings.VarType.Number, "Side offset",
        "Moves the camera over your right or left shoulder. Centered is the game's normal view; "
        .. "100% is the furthest the addon goes. The effect is stronger when you zoom in.",
        sliderOptions(Camera.SIDE_MIN, Camera.SIDE_MAX, Camera.SIDE_STEP,
            function(value) return Camera.Label(value, "Centered", "right", "left") end))
    addSetting("tilt", Settings.VarType.Number, "Tilt",
        "Tilts the camera up, so your character sits lower on the screen and you see more "
        .. "of what's ahead. Off is the game's own view; 100% is the strongest tilt. "
        .. "The further you zoom out, the stronger it is: close up it barely shows.",
        sliderOptions(Camera.TILT_MIN, Camera.TILT_MAX, Camera.TILT_STEP,
            function(value) return Camera.Label(value, "Off", "tilt") end))
    addSetting("lookDown", Settings.VarType.Number, "Tilt when looking down",
        "How much of the tilt stays when you look down at your character: the lower, the "
        .. "more it fades as the camera looks down; at 100% it stays as strong as with a level "
        .. "camera. Default is the game's own (about 25%). Only used while Tilt is on.",
        sliderOptions(Camera.LOOK_DOWN_MIN, Camera.LOOK_DOWN_MAX, Camera.LOOK_DOWN_STEP,
            function(value) return Camera.Label(value, "Default", "kept") end))
    addSetting("crosshair", Settings.VarType.Boolean, "Crosshair on your target",
        "With the controller UI on, puts its aiming dot (and its auto-attack timer) just "
        .. "below your target's nameplate, or the controller's soft target's, so it stays on "
        .. "what you attack as you both move. With no target, or nameplates off, it stays "
        .. "where the game aims. What the controller targets is still decided by the game.")
    addSetting("aim", Settings.VarType.Number, "Crosshair vertical offset",
        "Moves the controller's aiming dot up or down from just below your target's "
        .. "nameplate, in screen pixels, e.g. down onto its body. "
        .. "Default is just below the nameplate. With no target the dot stays where the game aims.",
        sliderOptions(Camera.AIM_MIN, Camera.AIM_MAX, Camera.AIM_STEP,
            function(value) return Camera.Label(value, "Default", "up", "down", "px") end))

    if Camera.AddNameplatesButton then Camera.AddNameplatesButton(layout) end   -- Nameplates.lua
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

-- /gco opens the settings; /gco debug ... goes to the debug suite (Debug.lua).
SLASH_GAMEPADCAMERAOFFSET1 = "/gco"
SlashCmdList.GAMEPADCAMERAOFFSET = function(message)
    local command, arguments = tostring(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "debug" and Camera.Debug then return Camera.Debug.Command(arguments) end
    Camera.Open()
end
