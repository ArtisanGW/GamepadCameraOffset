-- GamepadCameraOffset against a fake game: CVars with the temp layer, the Settings API,
-- frames, timers and events. From GamepadCameraOffset:  luajit tests/run.lua
local failed, passed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. "\n" .. err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local game
local function boot(gamepad, saved)
    game = { saved = {}, temp = {}, timers = {}, frames = {}, settings = {}, callbacks = {}, events = 0 }
    local defaults = { test_cameraOverShoulder = "0", test_cameraDynamicPitch = "0",
        test_cameraDynamicPitchBaseFovPad = "0.4", test_cameraDynamicPitchBaseFovPadFlying = "0.75",
        CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0" }
    for k, v in pairs(defaults) do game.saved[k] = v end
    local function fire(event, ...)
        for _, f in ipairs(game.frames) do if f.ev[event] and f.script then f.script(f, event, ...) end end
    end
    game.fire = fire
    local function changed(n) fire("CVAR_UPDATE", n, _G.C_CVar.GetCVar(n)) end
    if gamepad then game.temp.CameraKeepCharacterCentered = "1"; game.temp.CameraReduceUnexpectedMovement = "0" end
    _G.C_CVar = {
        GetCVar = function(n) if game.temp[n] ~= nil then return game.temp[n] end return game.saved[n] end,
        SetCVar = function(n, v) game.saved[n] = v; changed(n); return true end,
        SetTempCVar = function(n, v) game.temp[n] = v; changed(n) end,
        RemoveTempCVar = function(n) game.temp[n] = nil; changed(n) end,
        GetCVarDefault = function(n) return defaults[n] end,
    }
    _G.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    _G.C_Timer = { After = function(_, fn) game.timers[#game.timers + 1] = fn end }
    _G.CreateFrame = function()
        local f = { ev = {} }
        function f:RegisterEvent(e) self.ev[e] = true end
        function f:UnregisterEvent(e) self.ev[e] = nil end
        function f:SetScript(kind, fn) if kind == "OnUpdate" then self.update = fn else self.script = fn end end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        game.frames[#game.frames + 1] = f
        return f
    end
    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return 42 end } end,
        RegisterAddOnSetting = function(cat, variable, key, tbl, kind, label, def)
            if tbl[key] == nil then tbl[key] = def end
            local s = { variable = variable, key = key, tbl = tbl }
            game.settings[variable] = s
            return s
        end,
        SetOnValueChangedCallback = function(variable, fn) game.callbacks[variable] = fn end,
        CreateCheckbox = function() end,
        CreateSlider = function(_, setting, options) game.options = game.options or {}; game.options[setting.key] = options end,
        CreateSliderOptions = function(lo, hi, step)
            return { lo = lo, hi = hi, SetLabelFormatter = function(self, _, fn) self.format = fn end }
        end,
        RegisterAddOnCategory = function(cat) game.category = cat end,
        OpenToCategory = function(id) game.opened = id end,
    }
    _G.SlashCmdList = {}
    _G.UIParent = { GetHeight = function() return 768 end }
    game.zoom = 10
    _G.GetCameraZoom = function() return game.zoom end
    _G.GetCursorCenterPosition = function() return 0, 480 end
    _G.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
    _G.hooksecurefunc = function(t, m, fn) local orig = t[m]; t[m] = function(...) local r = orig(...); fn(...); return r end end
    game.saved.cameraFov = "90"
    game.recenters = 0
    _G.GamepadReticle = {
        GetEffectiveScale = function() return 1.5 end,
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, p, rel, rp, x, y) self.point = { p, rp, x, y } end,
        Recenter = function(self) game.recenters = game.recenters + 1; self.point = { "CENTER", "BOTTOM", 0, 320 } end,
    }
    _G.GamepadCameraOffsetDB = saved
    assert(loadfile("GamepadCameraOffset.lua"))("GamepadCameraOffset", {})
    fire("ADDON_LOADED", "GamepadCameraOffset")
end
local function frame() local t = game.timers; game.timers = {}; for _, fn in ipairs(t) do fn() end end
local function set(key, value)
    local s = game.settings["GamepadCameraOffset_" .. key]
    s.tbl[s.key] = value
    game.callbacks[s.variable](nil, s, value)
end
local get = function(n) return C_CVar.GetCVar(n) end

test("registers its page under Options > AddOns, with the defaults", function()
    boot(true, nil)
    eq(game.category.name, "GamepadCameraOffset")
    eq(GamepadCameraOffsetDB.enabled, true); eq(GamepadCameraOffsetDB.side, 40); eq(GamepadCameraOffsetDB.height, 35); eq(GamepadCameraOffsetDB.aim, 0)
    eq(game.options.side.format(40), "40% right"); eq(game.options.side.format(-25), "25% left"); eq(game.options.side.format(0), "Centered")
    eq(game.options.height.format(35), "35% higher"); eq(game.options.height.format(0), "Normal")
    eq(game.options.aim.format(10), "10% up"); eq(game.options.aim.format(-5), "5% down"); eq(game.options.aim.format(0), "Normal")
    SlashCmdList.GAMEPADCAMERAOFFSET("")
    eq(game.opened, 42, "/gco opens it")
end)

test("on a controller, entering the world un-centers the camera and sets both offsets", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(get("CameraKeepCharacterCentered"), "0", "the temp value wins over the controller's")
    eq(game.saved.CameraKeepCharacterCentered, "1", "your saved setting untouched")
    eq(get("test_cameraOverShoulder"), "1.2")
    eq(get("test_cameraDynamicPitch"), "1")
    eq(get("test_cameraDynamicPitchBaseFovPad"), "0.315", "35% of 0.9")
    eq(get("test_cameraDynamicPitchBaseFovPadFlying"), "0.315")
end)

test("the game re-centering (a switch to the controller) is undone on the next frame, once", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    C_CVar.SetTempCVar("CameraKeepCharacterCentered", "1")
    eq(#game.timers, 1, "one re-apply queued")
    frame()
    eq(get("CameraKeepCharacterCentered"), "0")
    eq(#game.timers, 0, "its own change queues nothing more")
end)

test("sliders apply at once; height Normal turns the pitch off", function()
    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("side", -50)
    eq(get("test_cameraOverShoulder"), "-1.5", "50% left")
    set("height", 0)
    eq(get("test_cameraDynamicPitch"), "0")
    set("side", 999)
    eq(get("test_cameraOverShoulder"), "3", "clamped")
end)

test("disabling puts the game's camera back: controller temp values, else none", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("enabled", false)
    eq(get("test_cameraOverShoulder"), "0")
    eq(get("test_cameraDynamicPitchBaseFovPad"), "0.4", "game default")
    eq(game.temp.CameraKeepCharacterCentered, "1", "the controller's own value back")
    C_CVar.SetTempCVar("CameraKeepCharacterCentered", "1")
    eq(#game.timers, 0, "disabled: the game's centering is left alone")

    boot(false, { enabled = true, side = 30, height = 20 })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("enabled", false)
    eq(game.temp.CameraKeepCharacterCentered, nil, "keyboard: no temp value left")
    eq(get("CameraKeepCharacterCentered"), "1")
end)

test("disabled at login touches nothing", function()
    boot(true, { enabled = false, side = 30, height = 20 })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(get("test_cameraOverShoulder"), "0")
    eq(game.temp.CameraKeepCharacterCentered, "1")
end)

local function tick() for _, f in ipairs(game.frames) do if f.update and f.shown then f.update(f) end end end
local function near(a, b, msg) if math.abs(a - b) > 0.01 then error((msg or "") .. ": expected " .. b .. ", got " .. a, 2) end end

test("controller: the crosshair moves left in line with the character, by the zoom", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local p = GamepadReticle.point
    -- 1.2 yd at 10 yd zoom, fov 90: 768 / (2 * 10 * 0.75) = 51.2 per yard
    near(p[3], -1.2 * 51.2, "x"); near(p[4], 320, "the game's aim height (480 / scale 1.5)")
    game.zoom = 20; tick()
    near(GamepadReticle.point[3], -1.2 * 25.6, "zooming out brings it back toward the middle")
    set("side", -50); tick()
    near(GamepadReticle.point[3], 1.5 * 25.6, "left shoulder: the character, and the dot, sit right")
    set("aim", 5)
    near(GamepadReticle.point[4], 320 + 0.05 * 768, "5% of the screen up")
end)

test("the game's own Recenter (a resize) is followed by ours", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    GamepadReticle:Recenter()
    near(GamepadReticle.point[3], -1.2 * 51.2, "put back in line")
end)

test("crosshair off, GamepadCameraOffset off or keyboard: the game's crosshair is left alone", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("crosshair", false)
    eq(GamepadReticle.point[3], 0, "recentered by the game's own code")
    tick()
    eq(GamepadReticle.point[3], 0, "and not moved again")
    set("crosshair", true)
    set("enabled", false)
    eq(GamepadReticle.point[3], 0)

    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame(); tick()
    eq(GamepadReticle.point, nil, "keyboard: never touched")
    eq(game.recenters, 0)
end)

test("a secret zoom leaves the crosshair where it was", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local x = GamepadReticle.point[3]
    game.zoom = { secret = true }; tick()
    eq(GamepadReticle.point[3], x)
end)

test("settings saved in yards and UI units are converted to percentages once", function()
    boot(true, { enabled = true, horizontal = 1.3, vertical = 0.3, crosshair = true, crosshairHeight = -120 })
    local d = GamepadCameraOffsetDB
    eq(d.side, 45, "1.3 of 3 yd, to the nearest 5%"); eq(d.height, 35, "0.3 of 0.9"); eq(d.aim, -16, "-120 of 768")
    eq(d.horizontal, nil); eq(d.vertical, nil); eq(d.crosshairHeight, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(get("test_cameraOverShoulder"), "1.35")
end)

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
