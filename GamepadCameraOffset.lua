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
    DEFAULTS = { enabled = true, horizontal = 1.2, vertical = 0.3, crosshair = true, crosshairHeight = 0 },
    H_MIN = -3, H_MAX = 3, H_STEP = 0.1,      -- yards; negative is the left shoulder
    V_MIN = 0, V_MAX = 0.9, V_STEP = 0.05,     -- share of the view kept above the character
    C_MIN = -200, C_MAX = 200, C_STEP = 5,     -- crosshair height nudge, UI units
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

local function db()
    if type(GamepadCameraOffsetDB) ~= "table" then GamepadCameraOffsetDB = {} end
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
    set(Cam.HORIZONTAL, clamp(d.horizontal, Cam.H_MIN, Cam.H_MAX, Cam.DEFAULTS.horizontal))
    local v = clamp(d.vertical, Cam.V_MIN, Cam.V_MAX, Cam.DEFAULTS.vertical)
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
-- the vertical offset tilts the camera around the character, which stays on
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
    y = y + (tonumber(db().crosshairHeight) or 0)
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
    add("horizontal", Settings.VarType.Number, "Horizontal offset",
        "How far the camera sits to the side of your character, in yards. "
        .. "Positive is over the right shoulder, negative over the left, 0 centered.",
        sliderOptions(Cam.H_MIN, Cam.H_MAX, Cam.H_STEP, function(v) return string.format("%.1f yd", v) end))
    add("vertical", Settings.VarType.Number, "Vertical offset",
        "How much of the view is kept above your character, which moves your "
        .. "character down the screen. Stronger the further you zoom out. 0 is the game's normal view.",
        sliderOptions(Cam.V_MIN, Cam.V_MAX, Cam.V_STEP, function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end))
    add("crosshair", Settings.VarType.Boolean, "Crosshair follows your character",
        "With the controller UI on, moves its aiming dot sideways so it stays in line with "
        .. "your character as the horizontal offset and your zoom change. Only the dot moves: "
        .. "what the controller targets is still decided by the game.")
    add("crosshairHeight", Settings.VarType.Number, "Crosshair height",
        "Moves the controller's aiming dot up or down from where the game puts it.",
        sliderOptions(Cam.C_MIN, Cam.C_MAX, Cam.C_STEP, function(v) return string.format("%+d", math.floor(v + 0.5)) end))

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
