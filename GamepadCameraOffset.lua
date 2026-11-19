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
local ADDON = ...

local Cam = {
    HORIZONTAL = "test_cameraOverShoulder",
    PITCH = "test_cameraDynamicPitch",
    PAD = "test_cameraDynamicPitchBaseFovPad",
    PAD_FLYING = "test_cameraDynamicPitchBaseFovPadFlying",
    CENTERED = "CameraKeepCharacterCentered",
    REDUCE = "CameraReduceUnexpectedMovement",
    -- What Blizzard's controller UI puts on the temp layer (Core.lua), put back on disable.
    PAD_TEMP = { CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0" },
    -- Every slider is a percentage. side: -100 (left) to 100 (right), 100% being
    -- SIDE_YARDS. height: 0 to 100, 100% being HEIGHT_MAX of the view kept above
    -- the character. aim: -25 (down) to 25 (up), in percent of the screen height.
    DEFAULTS = { enabled = true, side = 40, height = 35, crosshair = true, aim = 0 },
    SIDE_MIN = -100, SIDE_MAX = 100, SIDE_STEP = 5,
    HEIGHT_MIN = 0, HEIGHT_MAX_PCT = 100, HEIGHT_STEP = 5,
    AIM_MIN = -25, AIM_MAX = 25, AIM_STEP = 1,
    SIDE_YARDS = 3,      -- test_cameraOverShoulder at 100%
    HEIGHT_MAX = 0.9,    -- test_cameraDynamicPitchBaseFovPad at 100%
    -- Where the character sits on screen. The camera aims at the character, then
    -- slides sideways by the shoulder offset, so the character sits that many
    -- yards left of the middle, seen from the zoom distance. At cameraFov 90 the
    -- view is 90 degrees across a 4:3 screen, so tan(half its height) is 3/4 of
    -- tan(half the fov).
    FOV = 90,                  -- cameraFov when the CVar can't be read
    FOV_HEIGHT = 0.75,         -- 4:3: the height's share of the width
    MIN_ZOOM = 1.5,            -- yards; closer counts as this (first person)
    MOVE = 0.5,                -- UI units the crosshair must move before it's placed again
}
_G.GamepadCameraOffset = Cam

local CV = C_CVar or {}

local function get(name)
    local fn = CV.GetCVar or GetCVar
    local ok, v = pcall(fn, name)
    return ok and v or nil
end

local function set(name, value)
    local fn = CV.SetCVar or SetCVar
    pcall(fn, name, tostring(value))
end

local function setTemp(name, value)
    if type(CV.SetTempCVar) == "function" then pcall(CV.SetTempCVar, name, tostring(value)) end
end

local function dropTemp(name)
    if type(CV.RemoveTempCVar) == "function" then pcall(CV.RemoveTempCVar, name) end
end

local function default(name, fallback)
    local fn = CV.GetCVarDefault or GetCVarDefault
    if type(fn) ~= "function" then return fallback end
    local ok, v = pcall(fn, name)
    return ok and v or fallback
end

local function controllerUI()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function"
        and InputUtil.IsGamepadUIEnabled() == true
end

local function round(v, step) return math.floor(v / step + 0.5) * step end

-- Settings saved before the sliders were percentages (yards, a 0-0.9 share, UI
-- units) are converted once, to the nearest step.
local function migrate(d)
    local h, v, c = tonumber(d.horizontal), tonumber(d.vertical), tonumber(d.crosshairHeight)
    if d.side == nil and h then
        d.side = math.max(Cam.SIDE_MIN, math.min(Cam.SIDE_MAX, round(h / Cam.SIDE_YARDS * 100, Cam.SIDE_STEP)))
    end
    if d.height == nil and v then
        d.height = math.max(Cam.HEIGHT_MIN, math.min(Cam.HEIGHT_MAX_PCT, round(v / Cam.HEIGHT_MAX * 100, Cam.HEIGHT_STEP)))
    end
    if d.aim == nil and c then
        local screen = UIParent and UIParent:GetHeight() or 768
        if not screen or screen <= 0 then screen = 768 end
        d.aim = math.max(Cam.AIM_MIN, math.min(Cam.AIM_MAX, round(c / screen * 100, Cam.AIM_STEP)))
    end
    d.horizontal, d.vertical, d.crosshairHeight = nil, nil, nil
end

local function db()
    if type(GamepadCameraOffsetDB) ~= "table" then GamepadCameraOffsetDB = {} end
    migrate(GamepadCameraOffsetDB)
    for k, v in pairs(Cam.DEFAULTS) do
        if GamepadCameraOffsetDB[k] == nil then GamepadCameraOffsetDB[k] = v end
    end
    return GamepadCameraOffsetDB
end

local function clamp(v, lo, hi, fallback)
    v = tonumber(v)
    if not v then return fallback end
    return math.max(lo, math.min(hi, v))
end

-- Whether GamepadCameraOffset's values are on the camera now (so disabling knows to undo them).
local applied = false

function Cam.Apply()
    local d = db()
    if not d.enabled then return Cam.Remove() end
    applied = true
    setTemp(Cam.CENTERED, 0)
    setTemp(Cam.REDUCE, 0)
    local side = clamp(d.side, Cam.SIDE_MIN, Cam.SIDE_MAX, Cam.DEFAULTS.side)
    set(Cam.HORIZONTAL, side / 100 * Cam.SIDE_YARDS)
    local v = clamp(d.height, Cam.HEIGHT_MIN, Cam.HEIGHT_MAX_PCT, Cam.DEFAULTS.height) / 100 * Cam.HEIGHT_MAX
    set(Cam.PITCH, v > 0 and 1 or 0)
    set(Cam.PAD, v)
    set(Cam.PAD_FLYING, v)
    Cam.WatchCrosshair()
end

-- Puts the game's own values back: its defaults for the camera CVars, and on
-- the temp layer what the controller UI had there (nothing on keyboard).
function Cam.Remove()
    if not applied then return Cam.WatchCrosshair() end
    applied = false
    set(Cam.HORIZONTAL, default(Cam.HORIZONTAL, "0"))
    set(Cam.PITCH, default(Cam.PITCH, "0"))
    set(Cam.PAD, default(Cam.PAD, "0"))
    set(Cam.PAD_FLYING, default(Cam.PAD_FLYING, "0"))
    for name, value in pairs(Cam.PAD_TEMP) do
        if controllerUI() then setTemp(name, value) else dropTemp(name) end
    end
    Cam.WatchCrosshair()
end

-- The crosshair: the controller UI's GamepadReticle, a small dot Blizzard puts
-- at the screen's middle (x) and the engine's aim height (GetCursorCenterPosition).
-- It's a plain frame, not a protected one, so it moves in combat too. Blizzard
-- puts it back on a resize (GamepadReticleMixin:Recenter), which is hooked.
-- Moving it only moves the dot: what the controller's soft targeting picks is
-- decided by the game, not by the dot.

local function plain(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
    return v
end

local function number(name)
    return tonumber(plain(get(name)))
end

-- The character's offset from the screen's middle, in UIParent units (x only:
-- the height setting tilts the camera around the character, which stays on
-- the middle line).
function Cam.CharacterX()
    local shoulder = number(Cam.HORIZONTAL) or 0
    if shoulder == 0 then return 0 end
    local zoom = type(GetCameraZoom) == "function" and tonumber(plain(GetCameraZoom())) or nil
    if not zoom then return nil end
    local fov = number("cameraFov") or Cam.FOV
    if fov <= 0 then fov = Cam.FOV end
    local tanHalfHeight = Cam.FOV_HEIGHT * math.tan(math.rad(fov) / 2)
    local perYard = UIParent:GetHeight() / (2 * math.max(zoom, Cam.MIN_ZOOM) * tanHalfHeight)
    return -shoulder * perYard
end

local reticle   -- { x, y } where it was last put, or nil when it's Blizzard's

local function reticleOn()
    local d = db()
    return d.enabled and d.crosshair and controllerUI() and type(GamepadReticle) == "table"
end

local function centerY(r)
    local scale = r:GetEffectiveScale()
    if type(GetCursorCenterPosition) ~= "function" or not scale or scale <= 0 then return nil end
    local _, y = GetCursorCenterPosition()
    y = tonumber(plain(y))
    return y and y / scale or nil
end

function Cam.PlaceCrosshair(force)
    local r = _G.GamepadReticle
    if not reticleOn() then
        if reticle and type(r) == "table" then
            reticle = nil
            if type(r.Recenter) == "function" then r:Recenter() end
        end
        return
    end
    local x, y = Cam.CharacterX(), centerY(r)
    if not x or not y then return end
    local aim = clamp(db().aim, Cam.AIM_MIN, Cam.AIM_MAX, 0)
    y = y + aim / 100 * UIParent:GetHeight()
    if not force and reticle and math.abs(reticle.x - x) < Cam.MOVE and math.abs(reticle.y - y) < Cam.MOVE then return end
    reticle = { x = x, y = y }
    r:ClearAllPoints()
    r:SetPoint("CENTER", UIParent, "BOTTOM", x, y)
end

-- Follows the zoom every frame while the crosshair is on (placing it only when
-- it moved), and takes it back after Blizzard's own Recenter.
local follower = CreateFrame("Frame")
follower:Hide()   -- shown by WatchCrosshair, once the saved settings are in
follower:SetScript("OnUpdate", function(self)
    Cam.PlaceCrosshair()
    if not reticleOn() then self:Hide() end
end)
local hooked = false
function Cam.WatchCrosshair()
    local r = _G.GamepadReticle
    if not hooked and type(r) == "table" and type(r.Recenter) == "function" and type(hooksecurefunc) == "function" then
        hooked = true
        hooksecurefunc(r, "Recenter", function()
            if reticleOn() then Cam.PlaceCrosshair(true) else reticle = nil end
        end)
    end
    if reticleOn() then follower:Show() else follower:Hide() end
    Cam.PlaceCrosshair(true)
end

-- Apply on the next frame, once, however many reasons came in this frame.
local pending = false
function Cam.Soon()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        Cam.Apply()
    end)
end

-- Settings: Options > AddOns > GamepadCameraOffset

-- A slider's label: zero as a word ("Centered", "Normal"), the rest as a whole
-- percentage with a direction ("40% right", "10% down").
function Cam.Label(v, zero, up, down)
    local pct = math.floor(math.abs(tonumber(v) or 0) + 0.5)
    if pct == 0 then return zero end
    return string.format("%d%% %s", pct, ((tonumber(v) or 0) < 0 and down) or up)
end

local function sliderOptions(lo, hi, step, format)
    local o = Settings.CreateSliderOptions(lo, hi, step)
    local right = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        and MinimalSliderWithSteppersMixin.Label.Right
    if right and o.SetLabelFormatter then o:SetLabelFormatter(right, format) end
    return o
end

function Cam.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local d = db()
    local category = Settings.RegisterVerticalLayoutCategory("GamepadCameraOffset")
    Cam.category = category

    local function add(key, kind, label, tooltip, options)
        local variable = "GamepadCameraOffset_" .. key
        local setting = Settings.RegisterAddOnSetting(category, variable, key, d, kind, label, Cam.DEFAULTS[key])
        Settings.SetOnValueChangedCallback(variable, function() Cam.Apply() end)
        if kind == Settings.VarType.Boolean then
            Settings.CreateCheckbox(category, setting, tooltip)
        else
            Settings.CreateSlider(category, setting, options, tooltip)
        end
    end

    add("enabled", Settings.VarType.Boolean, "Enable",
        "Moves the camera with the settings below, on keyboard and on a controller. "
        .. "Turned off, the game's own camera comes back.\n\n"
        .. "These are the game's experimental camera settings: the first change in a "
        .. "session shows its warning. Accept keeps them.")
    add("side", Settings.VarType.Number, "Side offset",
        "Moves the camera over your right or left shoulder. Centered is the game's normal view; "
        .. "100% is the furthest the addon goes. The effect is stronger when you zoom in.",
        sliderOptions(Cam.SIDE_MIN, Cam.SIDE_MAX, Cam.SIDE_STEP,
            function(v) return Cam.Label(v, "Centered", "right", "left") end))
    add("height", Settings.VarType.Number, "Height",
        "Raises the camera's view so your character sits lower on the screen. Normal is the game's "
        .. "own view; 100% is the furthest the addon goes. The effect is stronger when you zoom out.",
        sliderOptions(Cam.HEIGHT_MIN, Cam.HEIGHT_MAX_PCT, Cam.HEIGHT_STEP,
            function(v) return Cam.Label(v, "Normal", "higher") end))
    add("crosshair", Settings.VarType.Boolean, "Crosshair follows your character",
        "With the controller UI on, moves its aiming dot sideways so it stays in line with "
        .. "your character as the side offset and your zoom change. Only the dot moves: "
        .. "what the controller targets is still decided by the game.")
    add("aim", Settings.VarType.Number, "Crosshair height",
        "Moves the controller's aiming dot up or down from where the game puts it, "
        .. "in percent of the screen's height. Normal is the game's own place.",
        sliderOptions(Cam.AIM_MIN, Cam.AIM_MAX, Cam.AIM_STEP,
            function(v) return Cam.Label(v, "Normal", "up", "down") end))

    Settings.RegisterAddOnCategory(category)
end

function Cam.Open()
    if Cam.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(Cam.category:GetID())
    end
end

-- Events

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CVAR_UPDATE")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        events:UnregisterEvent("ADDON_LOADED")
        db()
        pcall(Cam.RegisterSettings)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The controller UI sets its temp values around now too: apply after it.
        Cam.Soon()
    elseif event == "CVAR_UPDATE" then
        -- The game took the camera back (a reload, a switch to the controller).
        if type(name) == "string" and name:lower() == Cam.CENTERED:lower()
            and db().enabled and get(Cam.CENTERED) ~= "0" then
            Cam.Soon()
        end
    end
end)

SLASH_GAMEPADCAMERAOFFSET1 = "/gco"
SlashCmdList.GAMEPADCAMERAOFFSET = function() Cam.Open() end
