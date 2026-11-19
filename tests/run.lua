-- GamepadCameraOffset against a fake game: CVars with the temp layer, the Settings API,
-- frames, timers and events. From GamepadCameraOffset:  luajit tests/run.lua
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; reportLine("FAIL " .. name .. "\n" .. err) end
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
    local function newFakeRegion()
        local fakeRegion = {}
        for _, methodName in ipairs({ "SetAllPoints", "SetColorTexture", "SetPoint", "SetWidth", "SetSize", "SetFrameStrata", "RegisterForClicks" }) do
            fakeRegion[methodName] = function() end
        end
        function fakeRegion:SetText(text) self.label = text end
        function fakeRegion:SetAttribute(key, value) self.attributes = self.attributes or {}; self.attributes[key] = value end
        function fakeRegion:CreateTexture() return newFakeRegion() end
        function fakeRegion:CreateFontString() return newFakeRegion() end
        return fakeRegion
    end
    _G.CreateFrame = function(frameType, name, parent, template)
        local fakeFrame = newFakeRegion()
        fakeFrame.ev, fakeFrame.frameType, fakeFrame.name, fakeFrame.template = {}, frameType, name, template
        if name then _G[name] = fakeFrame end
        function fakeFrame:RegisterEvent(eventName) self.ev[eventName] = true end
        function fakeFrame:UnregisterEvent(eventName) self.ev[eventName] = nil end
        function fakeFrame:SetScript(scriptType, handler)
            if scriptType == "OnUpdate" then self.update = handler
            elseif scriptType == "OnClick" then self.click = handler
            else self.script = handler end
        end
        function fakeFrame:Show() self.shown = true end
        function fakeFrame:Hide() self.shown = false end
        game.frames[#game.frames + 1] = fakeFrame
        return fakeFrame
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
        GetPoint = function(self) local q = self.point; if q then return q[1], UIParent, q[2], q[3], q[4] end end,
        Recenter = function(self) game.recenters = game.recenters + 1; self.point = { "CENTER", "BOTTOM", 0, 320 } end,
    }
    game.combat = false
    _G.InCombatLockdown = function() return game.combat end
    _G.GetBuildInfo = function() return "1.60.1", "70959", "", 16001 end
    _G.GamepadCameraOffsetDB = saved
    _G.GamepadCameraOffsetDebugDB = nil
    _G.GamepadCameraOffsetDebugBox = nil
    local printed = {}
    game.printed = printed
    _G.print = function(t) printed[#printed + 1] = t end
    local ns = {}
    assert(loadfile("GamepadCameraOffset.lua"))("GamepadCameraOffset", ns)
    assert(loadfile("Debug.lua"))("GamepadCameraOffset", ns)
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

-- /gco debug: the in-game suite, run here against the fake game.
local function runUntilNoTimersLeft()
    for _ = 1, 200 do if #game.timers == 0 then return end; frame() end
    error("the debug run never ended")
end
local function describeSavedSettings()
    local saved = GamepadCameraOffsetDB
    return string.format("%s %s %s %s %s", tostring(saved.enabled), saved.side, saved.height, tostring(saved.crosshair), saved.aim)
end

test("/gco debug on a controller: every check passes, settings come back, findings saved", function()
    boot(true, { enabled = true, side = 30, height = 20, crosshair = true, aim = -5 })
    game.fire("PLAYER_LOGIN"); game.fire("PLAYER_ENTERING_WORLD"); frame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    runUntilNoTimersLeft()
    local runs = GamepadCameraOffsetDebugDB.runs
    eq(#runs, 1, "one run saved")
    local run = runs[1]
    for _, check in ipairs(run.checks) do
        if check.result ~= "pass" then
            error(check.result .. ": " .. check.name .. " expected " .. tostring(check.expected)
                .. " got " .. tostring(check.actual) .. " " .. tostring(check.note))
        end
    end
    eq(run.failed, 0); eq(run.skipped, 0); eq(run.passed > 20, true, "passed " .. run.passed)
    eq(run.environment.controllerUI, true); eq(run.environment.build, "70959"); eq(run.environment.settings.side, 30)
    eq(describeSavedSettings(), "true 30 20 true -5", "your settings back")
    eq(get("test_cameraOverShoulder"), "0.9", "and applied")
    eq(GamepadCameraOffsetDebugDB.settingsToRestore, nil)
    local reloadBox = GamepadCameraOffsetDebugBox
    eq(reloadBox.shown, true, "reload box shown")
    eq(reloadBox.reloadButton.attributes.macrotext, "/reload"); eq(reloadBox.reloadButton.template, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    reloadBox.laterButton.click(); eq(reloadBox.shown, false, "Later hides it")
end)

test("/gco debug on keyboard: crosshair checks skipped, the rest pass", function()
    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    runUntilNoTimersLeft()
    local run = GamepadCameraOffsetDebugDB.runs[1]
    eq(run.failed, 0); eq(run.skipped > 0, true)
    for _, check in ipairs(run.checks) do
        if check.result == "skip" then eq(check.note, "controller UI off") end
    end
end)

test("/gco debug: a fight stops it, settings come back, the box waits for the fight's end", function()
    boot(true, { enabled = true, side = 30, height = 20, crosshair = true, aim = 0 })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    frame(); frame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    eq(GamepadCameraOffsetDebugDB.runs[1].stopped, "combat")
    eq(describeSavedSettings(), "true 30 20 true 0")
    eq(GamepadCameraOffsetDebugBox, nil, "no box in combat")
    runUntilNoTimersLeft()
    eq(#GamepadCameraOffsetDebugDB.runs, 1, "nothing ran after the stop")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    eq(GamepadCameraOffsetDebugBox.shown, true, "shown once the fight is over")
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    eq(#game.timers > 0, true, "and out of combat it runs again")
end)

test("/gco debug: refused in combat; last and clear", function()
    boot(true, nil)
    game.combat = true
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    eq(GamepadCameraOffsetDebugDB, nil, "nothing started, nothing saved")
    eq(game.printed[#game.printed]:match("not in combat") ~= nil, true)
    game.combat = false
    SlashCmdList.GAMEPADCAMERAOFFSET("debug last")
    eq(game.printed[#game.printed]:match("no saved run") ~= nil, true)
    SlashCmdList.GAMEPADCAMERAOFFSET("debug"); runUntilNoTimersLeft()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug last")
    eq(game.printed[#game.printed]:match("0 failed") ~= nil, true, game.printed[#game.printed])
    SlashCmdList.GAMEPADCAMERAOFFSET("debug clear")
    eq(#GamepadCameraOffsetDebugDB.runs, 0)
    SlashCmdList.GAMEPADCAMERAOFFSET("")
    eq(game.opened, 42, "plain /gco still opens the settings")
end)

test("a reload in the middle of a run: your settings are back at the next login", function()
    boot(true, { enabled = true, side = -100, height = 0, crosshair = false, aim = 0 })
    GamepadCameraOffsetDebugDB = { runs = {}, settingsToRestore = { enabled = true, side = 30, height = 20, crosshair = true, aim = 3 } }
    game.fire("PLAYER_LOGIN")
    eq(describeSavedSettings(), "true 30 20 true 3")
    eq(GamepadCameraOffsetDebugDB.settingsToRestore, nil)
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
