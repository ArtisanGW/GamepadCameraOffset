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
-- releaseBuild: as in the release zip, without Debug.lua (see .pkgmeta).
local function boot(gamepad, saved, releaseBuild)
    game = { saved = {}, temp = {}, timers = {}, frames = {}, settings = {}, callbacks = {}, events = 0 }
    local defaults = { test_cameraOverShoulder = "0", test_cameraDynamicPitch = "0",
        test_cameraDynamicPitchBaseFovPad = "0.4", test_cameraDynamicPitchBaseFovPadFlying = "0.75",
        test_cameraDynamicPitchBaseFovPadDownScale = "0.25",
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
        CreateColorSwatch = function(_, setting) game.swatch = setting end,
        RegisterProxySetting = function(cat, variable, kind, label, def, getValue, setValue)
            local s = { variable = variable, key = variable, label = label, getValue = getValue, setValue = setValue }
            game.settings[variable] = s
            return s
        end,
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
    _G.hooksecurefunc = function(t, m, fn)
        if type(t) == "string" then t, m, fn = _G, t, m end   -- the global form: hooksecurefunc("Name", fn)
        local orig = t[m]; t[m] = function(...) local r = orig(...); fn(...); return r end
    end
    game.consoleCommands = {}
    _G.ConsoleExec = function(command) game.consoleCommands[#game.consoleCommands + 1] = command end
    game.internalEvents = { EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED = true }
    _G.GameEvent = { UnregisterInternalEvent = function(event) game.internalEvents[event] = nil end }
    game.popupsShown = {}
    _G.StaticPopup_Show = function(popupName) game.popupsShown[popupName] = true end
    _G.StaticPopup_Hide = function(popupName) game.popupsShown[popupName] = nil end
    game.saved.cameraFov = "90"
    game.recenters = 0
    _G.GamepadReticle = {
        GetEffectiveScale = function() return 1.5 end,
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, p, rel, rp, x, y) self.point = { p, rp, x, y, relativeTo = rel } end,
        -- Like the game: anchored to a nameplate (a restricted region), it can't be measured.
        GetPoint = function(self)
            local q = self.point
            if q and type(q.relativeTo) == "table" and q.relativeTo.restricted then
                error("GamepadReticle:GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]")
            end
            if q then return q[1], q.relativeTo or UIParent, q[2], q[3], q[4] end
        end,
        Recenter = function(self) game.recenters = game.recenters + 1; self.point = { "CENTER", "BOTTOM", 0, 320 } end,
        Icons = { StandardIcon = { color = { 1, 1, 1, 1 }, SetVertexColor = function(self, r, g, b, a) self.color = { r, g, b, a } end } },
    }
    -- Units and their nameplates: game.units[unit] = true, game.nameplates[unit] = a frame.
    game.units, game.nameplates = {}, {}
    _G.UnitExists = function(unit) return game.units[unit] == true end
    _G.GetPhysicalScreenSize = function() return 2304, 1536 end
    game.buttons = {}
    _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip)
        return { name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip }
    end
    local function addInitializer(_, initializer) game.buttons[#game.buttons + 1] = initializer end
    _G.SettingsPanel = { GetLayout = function() return { AddInitializer = addInitializer } end }
    -- The game's color picker: shown or not, its hooks, and its ColorSelect's HSV.
    game.time = 100
    _G.GetTime = function() return game.time end
    game.picker = { hooks = {}, hsv = { 120, 1, 0.5 } }
    _G.ColorPickerFrame = {
        IsShown = function() return game.picker.shown == true end,
        HookScript = function(_, script, fn) game.picker.hooks[script] = fn end,
        Show = function() game.picker.shown = true; if game.picker.hooks.OnShow then game.picker.hooks.OnShow() end end,
        Hide = function() game.picker.shown = false; if game.picker.hooks.OnHide then game.picker.hooks.OnHide() end end,
        Content = {
            ColorPicker = {
                GetColorHSV = function() return game.picker.hsv[1], game.picker.hsv[2], game.picker.hsv[3] end,
                SetColorHSV = function(_, h, s, v) game.picker.hsv = { h, s, v } end,
                GetColorAlpha = function() return game.picker.alpha end,
                SetColorAlpha = function(_, a) game.picker.alpha = a end,
                SetWidth = function() end,
                Alpha = { Show = function() game.picker.barShown = true end },
                AlphaThumb = { Show = function() end },
            },
            AlphaBackground = { Show = function() end },
        },
        SetWidth = function() end,
    }
    game.cameraStickY, game.moveStickX, game.moveStickY = 0, 0, 0
    game.padUp, game.padDown = false, false
    _G.C_GamePad = {
        GetDeviceMappedState = function()
            return { stickCount = 2, sticks = { { x = game.moveStickX, y = game.moveStickY }, { x = 0, y = game.cameraStickY } },
                buttonCount = 3, buttons = { false, game.padUp, game.padDown } }
        end,
        ButtonIndexToConfigName = function(index) return ({ [0] = "PAD1", [1] = "PADDUP", [2] = "PADDDOWN" })[index] end,
        StickIndexToConfigName = function(index) return index == 0 and "Movement" or "Camera" end,
    }
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit) return game.nameplates[unit] end }
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
    if not releaseBuild then assert(loadfile("Debug.lua"))("GamepadCameraOffset", ns) end
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
    eq(game.category.name, "Gamepad Camera Offset", "spaced in the settings window")
    eq(GamepadCameraOffsetDB.enabled, true); eq(GamepadCameraOffsetDB.side, 40); eq(GamepadCameraOffsetDB.tilt, 50); eq(GamepadCameraOffsetDB.aim, 0)
    eq(game.options.side.format(40), "40% right"); eq(game.options.side.format(-25), "25% left"); eq(game.options.side.format(0), "Centered")
    eq(game.options.tilt.format(35), "35% tilt"); eq(game.options.tilt.format(0), "Off")
    eq(game.options.aim.format(10), "10 px up"); eq(game.options.aim.format(-5), "5 px down"); eq(game.options.aim.format(0), "Default")
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
    eq(get("test_cameraDynamicPitchBaseFovPad"), "0.4375", "tilt 50%: halfway from 0.75 to 0.125")
    eq(get("test_cameraDynamicPitchBaseFovPadFlying"), "0.4375")
    eq(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.5", "tilt when looking down: 50% by default")
end)

test("ActionCam basic runs once before the first apply; off when disabled, basic again when enabled", function()
    boot(false, nil)
    eq(#game.consoleCommands, 0, "nothing before entering the world")
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("side", 20); set("tilt", 70)
    eq(table.concat(game.consoleCommands, ","), "ActionCam basic", "once, however many changes")
    set("enabled", false)
    eq(table.concat(game.consoleCommands, ","), "ActionCam basic,ActionCam off")
    set("enabled", true)
    eq(table.concat(game.consoleCommands, ","), "ActionCam basic,ActionCam off,ActionCam basic")
end)

test("disabled at login runs no ActionCam command", function()
    boot(false, { enabled = false })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(#game.consoleCommands, 0)
end)

test("the game's experimental warning: its event dropped at load, the popup hidden if shown", function()
    boot(false, nil)
    eq(game.internalEvents.EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED, nil, "the game no longer listens for it")
    StaticPopup_Show("EXPERIMENTAL_CVAR_WARNING")
    eq(game.popupsShown.EXPERIMENTAL_CVAR_WARNING, nil, "hidden at once")
    StaticPopup_Show("SOMETHING_ELSE")
    eq(game.popupsShown.SOMETHING_ELSE, true, "other popups untouched")
end)

test("tilt when looking down: the slider's percentage as the game's 0 to 1, labelled", function()
    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("lookDown", 80)
    eq(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.8")
    set("lookDown", 500)
    eq(get("test_cameraDynamicPitchBaseFovPadDownScale"), "1", "clamped")
    eq(game.options.lookDown.format(80), "80% kept"); eq(game.options.lookDown.format(0), "Default")
    set("lookDown", 0)
    eq(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.25", "Default: the game's own value")
    set("enabled", false)
    eq(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.25", "the game's default back")
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

test("sliders apply at once; tilt Off turns the pitch off", function()
    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("side", -50)
    eq(get("test_cameraOverShoulder"), "-1.5", "50% left")
    set("tilt", 0)
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

    boot(false, { enabled = true, side = 30, tilt = 20 })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    set("enabled", false)
    eq(game.temp.CameraKeepCharacterCentered, nil, "keyboard: no temp value left")
    eq(get("CameraKeepCharacterCentered"), "1")
end)

test("disabled at login touches nothing", function()
    boot(true, { enabled = false, side = 30, tilt = 20 })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(get("test_cameraOverShoulder"), "0")
    eq(game.temp.CameraKeepCharacterCentered, "1")
end)

local function tick() for _, f in ipairs(game.frames) do if f.update and f.shown then f.update(f) end end end
local function near(a, b, msg) if math.abs(a - b) > 0.01 then error((msg or "") .. ": expected " .. b .. ", got " .. a, 2) end end

local function onUpdateFramesShown()
    local count = 0
    for _, f in ipairs(game.frames) do if f.update and f.shown then count = count + 1 end end
    return count
end

test("controller, no target: the crosshair stays where the game aims, whatever the side and zoom, with nothing per frame", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local p = GamepadReticle.point
    near(p[3], 0, "x: the middle, where the controller's targeting aims")
    near(p[4], 320, "the game's aim height (480 / scale 1.5)")
    eq(GamepadReticle.point.relativeTo, UIParent)
    game.zoom = 20; set("side", -50)
    near(GamepadReticle.point[3], 0, "the side offset doesn't move it")
    set("aim", 5)
    near(GamepadReticle.point[4], 320, "the vertical offset is for targets: no target, the game's own height")
    eq(onUpdateFramesShown(), 0, "no frame runs every frame")
end)

test("controller, a target: the crosshair goes under its nameplate, re-placed only when the target or plates change", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local targetPlate, softPlate = { name = "target's plate" }, { name = "soft target's plate" }
    game.units.softenemy = true; game.nameplates.softenemy = softPlate
    game.fire("PLAYER_SOFT_ENEMY_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, softPlate, "no target of yours: the controller's soft target")
    eq(GamepadReticle.point[2], "BOTTOM"); eq(GamepadReticle.point[4], -12, "just below the nameplate")
    set("aim", -30)
    -- 30 px on a 1536 px tall screen: 15 of its 768 units, at the crosshair's scale 1.5: 10
    near(GamepadReticle.point[4], -12 - 10, "the vertical offset: 30 px down from there")
    eq(GamepadReticle.point.relativeTo, softPlate, "still on the nameplate")
    set("aim", 0)
    game.units.target = true; game.nameplates.target = targetPlate
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, targetPlate, "your target first")
    game.fire("PLAYER_TARGET_CHANGED"); game.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
    eq(#game.timers, 1, "several reasons in one frame: placed once, on the next frame")
    frame()
    game.nameplates.target = nil; game.nameplates.softenemy = nil
    game.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); frame()
    eq(GamepadReticle.point.relativeTo, UIParent, "no nameplate left (off screen): back where the game aims")
    game.nameplates.softenemy = softPlate
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate2"); frame()
    eq(GamepadReticle.point.relativeTo, UIParent,
        "a target without a nameplate (a friend, friendly plates off): never jumps to the soft target")
    local friendPlate = { name = "friend's plate" }
    game.nameplates.target = friendPlate
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate4"); frame()
    eq(GamepadReticle.point.relativeTo, friendPlate, "with friendly plates on: on the friend")
    near(GamepadReticle.point[3], 0)
    eq(onUpdateFramesShown(), 0, "still nothing per frame: the game moves the nameplate, and the dot with it")
end)

test("the game's own Recenter (a resize) is followed by ours", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local targetPlate = {}
    game.units.target = true; game.nameplates.target = targetPlate
    GamepadReticle:Recenter()
    eq(GamepadReticle.point.relativeTo, targetPlate, "put back on the target")
end)

test("crosshair off, GamepadCameraOffset off or keyboard: the game's crosshair is left alone", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    game.units.target = true; game.nameplates.target = {}
    set("crosshair", false)
    eq(GamepadReticle.point[3], 0, "recentered by the game's own code")
    eq(GamepadReticle.point[4], 320)
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, nil, "and not put on the target")
    set("crosshair", true)
    set("enabled", false)
    eq(GamepadReticle.point.relativeTo, nil, "off: the game's own place")

    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    game.units.target = true; game.nameplates.target = {}
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point, nil, "keyboard: never touched")
    eq(game.recenters, 0)
end)

test("the crosshair goes under the part of the nameplate you see: health bar, else the name", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local function part(visible) return { IsVisible = function() return visible end } end
    local healthBar, name = part(true), part(true)
    local plate = { UnitFrame = { healthBar = healthBar, name = name } }
    game.units.target = true; game.nameplates.target = plate
    game.fire("PLAYER_TARGET_CHANGED"); frame()
    eq(GamepadReticle.point.relativeTo, healthBar, "under the health bar")
    plate.UnitFrame.healthBar = part(false)
    game.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); frame()
    eq(GamepadReticle.point.relativeTo, name, "names only (a friendly player): under the name")
end)

test("controller: while the color picker is open for the crosshair color, the left stick moves on the wheel, the right sets brightness", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local driver = GamepadCameraOffset.brightnessDriver
    local function step(seconds) driver.update(driver, seconds) end
    ColorPickerFrame:Show()
    eq(driver.shown, false, "a picker opened by something else (the chat settings): left to the game")
    ColorPickerFrame:Hide()
    game.swatch.getValue()   -- the swatch reads the color as it opens the picker
    game.time = game.time + 0.1
    SlashCmdList.GAMEPADCAMERAOFFSET("color FFFFFF80")
    ColorPickerFrame:Show()
    eq(driver.shown, true, "opened for the crosshair color: the right stick drives the brightness")
    eq(ColorPickerFrame.hasOpacity, true, "the opacity bar put on the picker")
    eq(game.picker.barShown, true)
    near(game.picker.alpha, 128 / 255, "at the crosshair's opacity")
    game.padUp = true; step(0.5)
    near(game.picker.alpha, 128 / 255 + 0.25, "D-pad up: more solid (0.5 a second)")
    eq(GamepadCameraOffsetDB.crosshairColor:sub(7, 8), string.format("%02X", math.floor((128 / 255 + 0.25) * 255 + 0.5)),
        "and the crosshair with it")
    game.padUp, game.padDown = false, true; step(10)
    near(game.picker.alpha, 0, "D-pad down: see-through, not past 0")
    game.padDown = false
    ColorPickerFrame.opacityFunc()   -- the mouse on the bar: the picker's own callback
    eq(GamepadCameraOffsetDB.crosshairColor:sub(7, 8), "00")
    game.cameraStickY = 1; step(0.5)
    near(game.picker.hsv[3], 0.8, "stick up: brighter (0.6 a second)")
    eq(game.picker.hsv[1], 120, "the hue kept")
    game.cameraStickY = -1; step(5)
    near(game.picker.hsv[3], 0, "stick down: darker, not past black")
    game.cameraStickY = 0.1; step(1)
    near(game.picker.hsv[3], 0, "inside the dead zone: nothing")
    game.cameraStickY = 0

    -- The left stick: the point on the wheel. Hue 0 sits at the point (-1, 0).
    game.picker.hsv = { 0, 0, 1 }   -- the middle: white
    game.moveStickX = -1; step(0.5)
    near(game.picker.hsv[2], 0.4, "left: out from the middle, saturation 0.4 (0.8 a second)")
    near(game.picker.hsv[1], 0, "toward hue 0")
    game.moveStickX, game.moveStickY = 0, -1; step(0.5)
    local x, y = GamepadCameraOffset.WheelPoint(game.picker.hsv[1], game.picker.hsv[2])
    near(x, -0.4, "down: the point moves down"); near(y, -0.4)
    game.moveStickX, game.moveStickY = -1, 0; step(10)
    near(game.picker.hsv[2], 1, "never past the wheel's edge")
    near(game.picker.hsv[3], 1, "the brightness kept")
    game.moveStickX, game.moveStickY = 0.1, 0.1; local before = game.picker.hsv[1]; step(1)
    eq(game.picker.hsv[1], before, "inside the dead zone: nothing")
    game.moveStickX, game.moveStickY = 0, 0
    ColorPickerFrame:Hide()
    eq(driver.shown, false, "picker shut: nothing runs")
end)

local function dotColor()
    local color = GamepadReticle.Icons.StandardIcon.color
    return string.format("%.2f %.2f %.2f %.2f", color[1], color[2], color[3], color[4])
end

test("the crosshair's color: 32 bits RRGGBBAA, from /gco color or the settings swatch and an opacity slider, white when off", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(GamepadCameraOffsetDB.crosshairColor, "FFFFFFFF", "white by default")
    eq(dotColor(), "1.00 1.00 1.00 1.00")
    SlashCmdList.GAMEPADCAMERAOFFSET("color FF3030CC")
    eq(GamepadCameraOffsetDB.crosshairColor, "FF3030CC")
    eq(dotColor(), "1.00 0.19 0.19 0.80", "tinted at once")
    SlashCmdList.GAMEPADCAMERAOFFSET("color nonsense")
    eq(GamepadCameraOffsetDB.crosshairColor, "FF3030CC", "a wrong color changes nothing")
    eq(game.printed[#game.printed]:find("usage", 1, true) ~= nil, true, "and says how")
    SlashCmdList.GAMEPADCAMERAOFFSET("color #00ff00")
    eq(GamepadCameraOffsetDB.crosshairColor, "00FF00FF", "six digits: opaque")

    eq(#game.buttons, 0, "no button of ours opening the color picker (its controller bindings went on tainted)")
    local swatch, opacity = game.swatch, game.settings.GamepadCameraOffset_crosshairOpacity
    eq(swatch.label, "Crosshair color", "the settings page's own color swatch, which opens the picker itself")
    eq(swatch.getValue(), "FF00FF00", "the swatch's AARRGGBB: alpha FF, the color")
    swatch.setValue("ff0000ff")
    eq(GamepadCameraOffsetDB.crosshairColor, "0000FFFF", "the picked color, the opacity kept")
    swatch.setValue("nonsense")
    eq(GamepadCameraOffsetDB.crosshairColor, "0000FFFF", "a wrong value changes nothing")
    eq(opacity, nil, "no separate opacity slider: it's on the picker")
    GamepadCameraOffset.SetCrosshairOpacity(40)
    eq(GamepadCameraOffsetDB.crosshairColor, "0000FF66", "40% opacity")
    eq(dotColor(), "0.00 0.00 1.00 0.40", "tinted at once")
    swatch.setValue("ffff8000")
    eq(GamepadCameraOffsetDB.crosshairColor, "FF800066", "a new color keeps the opacity")
    SlashCmdList.GAMEPADCAMERAOFFSET("color 00FF00FF")

    set("crosshair", false)
    eq(dotColor(), "1.00 1.00 1.00 1.00", "crosshair setting off: the game's own white")
    set("crosshair", true)
    eq(dotColor(), "0.00 1.00 0.00 1.00", "and back")
end)

-- /gco debug: the in-game suite, run here against the fake game.
local function runUntilNoTimersLeft()
    for _ = 1, 200 do if #game.timers == 0 then return end; frame() end
    error("the debug run never ended")
end
local function describeSavedSettings()
    local saved = GamepadCameraOffsetDB
    return string.format("%s %s %s %s %s", tostring(saved.enabled), saved.side, saved.tilt, tostring(saved.crosshair), saved.aim)
end

test("/gco debug on a controller: every check passes, settings come back, findings saved", function()
    boot(true, { enabled = true, side = 30, tilt = 20, crosshair = true, aim = -5 })
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

test("/gco debug with a target: the crosshair on its nameplate is checked without measuring it (a restricted region)", function()
    boot(true, { enabled = true, side = 30, tilt = 20, crosshair = true, aim = -5 })
    game.units.target = true; game.nameplates.target = { restricted = true }
    game.fire("PLAYER_LOGIN"); game.fire("PLAYER_ENTERING_WORLD"); frame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    runUntilNoTimersLeft()
    local run = GamepadCameraOffsetDebugDB.runs[1]
    local onNameplate = 0
    for _, check in ipairs(run.checks) do
        if check.result ~= "pass" then
            error(check.result .. ": " .. check.name .. " expected " .. tostring(check.expected)
                .. " got " .. tostring(check.actual) .. " " .. tostring(check.note))
        end
        if check.name:find("on the target's nameplate", 1, true) then onNameplate = onNameplate + 1 end
    end
    eq(run.failed, 0)
    eq(onNameplate > 0, true, "the nameplate checks ran")
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
    boot(true, { enabled = true, side = 30, tilt = 20, crosshair = true, aim = 0 })
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
    GamepadCameraOffsetDebugDB = { runs = {}, settingsToRestore = { enabled = true, side = 30, tilt = 20, crosshair = true, aim = 3 } }
    game.fire("PLAYER_LOGIN")
    eq(describeSavedSettings(), "true 30 20 true 3")
    eq(GamepadCameraOffsetDebugDB.settingsToRestore, nil)
end)

-- The release zip (BigWigs packager, .github/workflows/release.yml) leaves the
-- debug suite out: .pkgmeta ignores the file, and its .toc line sits in a
-- do-not-package block, which the packager deletes.
test("the release leaves Debug.lua out: ignored by .pkgmeta, and gone from the release .toc", function()
    local function readFile(path) local file = assert(io.open(path)); local text = file:read("*a"); file:close(); return text end
    local packageRules = readFile(".pkgmeta")
    assert(packageRules:find("\n  %- Debug%.lua"), ".pkgmeta ignores Debug.lua")
    local releaseToc = readFile("GamepadCameraOffset.toc"):gsub("\r", "")
        :gsub("#@do%-not%-package@.-#@end%-do%-not%-package@\n?", "")   -- what the packager does
    local loadedFiles = {}
    for line in releaseToc:gmatch("[^\n]+") do
        if not line:find("^#") then loadedFiles[#loadedFiles + 1] = line end
    end
    eq(table.concat(loadedFiles, ","), "GamepadCameraOffset.lua", "the release .toc loads only the addon")
end)

test("without Debug.lua (the release), the addon works and /gco debug opens the settings", function()
    boot(true, {}, true)
    eq(GamepadCameraOffset.Debug, nil)
    game.fire("PLAYER_ENTERING_WORLD")
    frame()
    eq(C_CVar.GetCVar("CameraKeepCharacterCentered"), "0", "the camera offset still applies")
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    eq(game.opened, 42, "/gco debug opens the settings page")
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
