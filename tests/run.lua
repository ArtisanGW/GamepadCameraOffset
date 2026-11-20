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
-- nameplateOptions: { enemies, friends, classColors } as "0"/"1" (default all "0"),
-- refuse = true: the game won't take a change to them.
local function boot(gamepad, saved, releaseBuild, nameplateOptions)
    nameplateOptions = nameplateOptions or {}
    _G.C_AddOns = { DoesAddOnExist = function(name) return nameplateOptions.customizerInstalled == true and name == "GamepadCrosshairCustomizer" end }
    game = { saved = {}, temp = {}, timers = {}, frames = {}, settings = {}, callbacks = {}, events = 0 }
    local defaults = { test_cameraOverShoulder = "0", test_cameraDynamicPitch = "0",
        test_cameraDynamicPitchBaseFovPad = "0.4", test_cameraDynamicPitchBaseFovPadFlying = "0.75",
        test_cameraDynamicPitchBaseFovPadDownScale = "0.25",
        CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0" }
    for k, v in pairs(defaults) do game.saved[k] = v end
    game.saved.nameplateShowEnemies = nameplateOptions.enemies or "0"
    game.saved.nameplateShowFriendlyPlayers = nameplateOptions.friends or "0"
    game.saved.nameplateShowFriendlyClassColor = nameplateOptions.classColors or "0"
    local function fire(event, ...)
        for _, f in ipairs(game.frames) do if f.ev[event] and f.script then f.script(f, event, ...) end end
    end
    game.fire = fire
    local function changed(n) fire("CVAR_UPDATE", n, _G.C_CVar.GetCVar(n)) end
    if gamepad then game.temp.CameraKeepCharacterCentered = "1"; game.temp.CameraReduceUnexpectedMovement = "0" end
    _G.C_CVar = {
        GetCVar = function(n) if game.temp[n] ~= nil then return game.temp[n] end return game.saved[n] end,
        SetCVar = function(n, v)
            if nameplateOptions.refuse and n:find("^nameplate") then return false end
            game.saved[n] = v; changed(n); return true
        end,
        SetTempCVar = function(n, v) game.temp[n] = v; changed(n) end,
        RemoveTempCVar = function(n) game.temp[n] = nil; changed(n) end,
        GetCVarDefault = function(n) return defaults[n] end,
    }
    _G.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    _G.C_Timer = { After = function(_, fn) game.timers[#game.timers + 1] = fn end }
    local function newFakeRegion()
        local fakeRegion = {}
        for _, methodName in ipairs({ "SetAllPoints", "SetColorTexture", "SetPoint", "SetWidth", "SetSize", "SetFrameStrata", "RegisterForClicks", "EnableMouse",
            "SetAutoFocus", "SetFocus", "SetToplevel", "SetHeight", "ClearAllPoints", "SetJustifyH" }) do
            fakeRegion[methodName] = function() end
        end
        function fakeRegion:SetText(text) self.label = text end
        function fakeRegion:GetText() return self.label end
        function fakeRegion:HighlightText() self.highlighted = true end
        function fakeRegion:GetStringHeight() return 30 end
        function fakeRegion:SetShown(shown) self.shown = shown and true or false end
        function fakeRegion:IsShown() return self.shown == true end
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
            elseif scriptType == "PreClick" then self.preClick = handler
            elseif scriptType == "OnHide" then self.onHide = handler
            else self.script = handler end
        end
        function fakeFrame:Show() self.shown = true end
        function fakeFrame:Hide()
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.onHide then self.onHide(self) end
        end
        function fakeFrame:GetName() return self.name end
        function fakeFrame:Click() if self.click then self.click(self) end end
        game.frames[#game.frames + 1] = fakeFrame
        return fakeFrame
    end
    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            return { name = name, GetID = function() return 42 end }, { AddInitializer = function(_, initializer) game.buttons[#game.buttons + 1] = initializer end }
        end,
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
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit) return game.nameplates[unit] end }
    game.combat = false
    _G.InCombatLockdown = function() return game.combat end
    game.bindings, game.bindingOwners = {}, {}
    _G.SetOverrideBindingClick = function(owner, _, key, buttonName) game.bindings[key] = buttonName; game.bindingOwners[key] = owner end
    _G.ClearOverrideBindings = function(owner)
        for key, keyOwner in pairs(game.bindingOwners) do
            if keyOwner == owner then game.bindings[key], game.bindingOwners[key] = nil, nil end
        end
    end
    _G.GetBuildInfo = function() return "1.60.1", "70959", "", 16001 end
    _G.GamepadCameraOffsetDB = saved
    _G.GamepadCameraOffsetDebugDB = nil
    _G.GamepadCameraOffsetPopup = nil
    local printed = {}
    game.printed = printed
    _G.print = function(t) printed[#printed + 1] = t end
    local ns = {}
    assert(loadfile("GamepadCameraOffset.lua"))("GamepadCameraOffset", ns)
    assert(loadfile("Popup.lua"))("GamepadCameraOffset", ns)
    assert(loadfile("Nameplates.lua"))("GamepadCameraOffset", ns)
    assert(loadfile("RelatedAddon.lua"))("GamepadCameraOffset", ns)
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

test("no crosshair color here any more: the dot keeps its own, /gco color opens the settings, 1.0's saved color dropped", function()
    boot(true, { crosshairColor = "FF3030FF" })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(GamepadCameraOffsetDB.crosshairColor, nil, "1.0's saved color dropped")
    local color = GamepadReticle.Icons.StandardIcon.color
    eq(table.concat(color, " "), "1 1 1 1", "the dot's color untouched")
    eq(game.swatch, nil, "no color swatch on the page")
    SlashCmdList.GAMEPADCAMERAOFFSET("color FF3030FF")
    eq(game.opened, 42, "/gco color: just the settings")
    eq(table.concat(GamepadReticle.Icons.StandardIcon.color, " "), "1 1 1 1")
end)

-- Nameplates for "Crosshair on your target"

-- The popup (Popup.lua): shown or nil, its buttons' texts, and a click on one.
local function popup() local frame = _G.GamepadCameraOffsetPopup; return frame and frame.shown and frame or nil end
local function popupButtons()
    local frame, texts = _G.GamepadCameraOffsetPopup, {}
    for _, button in ipairs(frame.buttons) do if button.shown then texts[#texts + 1] = button.label end end
    if frame.reloadButton.shown then texts[#texts + 1] = "[secure] " .. frame.reloadButton.label end
    table.sort(texts)
    return table.concat(texts, ", ")
end
local function clickPopup(text)
    local frame = _G.GamepadCameraOffsetPopup
    for _, button in ipairs(frame.buttons) do if button.shown and button.label == text then return button:Click() end end
end
local function nameplatesBox() local frame = popup(); return frame and frame.text.label:find("nameplate", 1, true) and frame or nil end
local function nameplateValues()
    return game.saved.nameplateShowEnemies .. game.saved.nameplateShowFriendlyPlayers .. game.saved.nameplateShowFriendlyClassColor
end

test("first launch: a box says which nameplate settings are off; Turn on turns those on; asked once", function()
    boot(true, nil, false, { enemies = "1" })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    local box = nameplatesBox()
    eq(box and box.shown, true, "the box")
    eq(box.text.label:find("• friendly player nameplates\n• class colors on friendly player nameplates", 1, true) ~= nil, true,
        "names the two that are off: " .. box.text.label)
    eq(box.text.label:find("enemy nameplates", 1, true), nil, "not the one already on")
    eq(nameplateValues(), "100", "nothing changed before the click")
    eq(popupButtons(), "No thanks, Turn on"); eq(box.Border.template, "DialogBorderTemplate", "the game's dialog border")
    clickPopup("Turn on")
    eq(nameplateValues(), "111", "turned on")
    eq(box.shown, false, "closed")
    eq(GamepadCameraOffsetDB.nameplatesAsked, true)
    boot(true, GamepadCameraOffsetDB, false, { enemies = "1" })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(nameplatesBox(), nil, "the next launch doesn't ask again")
end)

test("on the controller: A turns the nameplates on, B says no; closing gives the buttons back", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(game.bindings.PAD1, "GamepadCameraOffsetPopupButton1", "A: Turn on")
    eq(game.bindings.PAD2, "GamepadCameraOffsetPopupButton2", "B: No thanks")
    eq(popup().hint.label, "A: Turn on      B: No thanks")
    _G[game.bindings.PAD1]:Click()
    eq(nameplateValues(), "111", "turned on with A")
    eq(game.bindings.PAD1, nil, "given back"); eq(game.bindings.PAD2, nil)
end)

test("No thanks changes nothing; the settings page's button asks again", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    clickPopup("No thanks")
    eq(nameplateValues(), "000", "nothing changed")
    eq(GamepadCameraOffsetDB.crosshair, true, "the crosshair setting kept")
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Nameplates" then button = initializer end end
    eq(button.buttonText, "Turn on nameplates")
    button.onClick()
    eq(nameplatesBox().shown, true, "asked again")
end)

test("no box when the nameplates are on, or the crosshair setting is off", function()
    boot(true, nil, false, { enemies = "1", friends = "1", classColors = "1" })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(nameplatesBox(), nil, "all on")
    boot(true, { crosshair = false })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(nameplatesBox(), nil, "crosshair setting off: not needed")
end)

test("first launch in a fight: the box waits for its end", function()
    boot(true, nil)
    game.combat = true
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    eq(nameplatesBox(), nil, "not in combat")
    eq(GamepadCameraOffsetDB.nameplatesAsked, true, "asked, after the fight")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    eq(nameplatesBox().shown, true, "after the fight")
end)

test("if the game won't take the nameplate settings, Crosshair on your target goes off and says why", function()
    boot(true, nil, false, { refuse = true })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    clickPopup("Turn on")
    eq(nameplateValues(), "000")
    eq(GamepadCameraOffsetDB.crosshair, false, "the setting that needs them, off")
    eq(game.printed[#game.printed]:find("couldn't turn on", 1, true) ~= nil, true, game.printed[#game.printed])
end)

test("without Gamepad Crosshair Customizer: a button shows its link to copy; with it, no button", function()
    boot(true, nil)
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Gamepad Crosshair Customizer" then button = initializer end end
    eq(button and button.buttonText, "Get Gamepad Crosshair Customizer")
    button.onClick()
    local box = popup()
    eq(box ~= nil, true, "the popup")
    eq(box.editBox:GetText(), "https://www.curseforge.com/projects/1818557", "its CurseForge page")
    eq(box.editBox.highlighted, true, "selected, ready for Ctrl+C")
    eq(popupButtons(), "Close, [secure] Reload", "a Reload for once it's installed")
    clickPopup("Close")
    eq(popup(), nil, "closed")
    boot(true, nil, false, { customizerInstalled = true })
    for _, initializer in ipairs(game.buttons) do eq(initializer.name ~= "Gamepad Crosshair Customizer", true, "installed: no button") end
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
    local reloadBox = popup()
    eq(reloadBox ~= nil, true, "reload popup shown")
    eq(reloadBox.reloadButton.attributes.macrotext, "/reload"); eq(reloadBox.reloadButton.template, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    eq(popupButtons(), "Later, [secure] Reload")
    clickPopup("Later"); eq(popup(), nil, "Later hides it")
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
    -- Nameplates on: no first-launch nameplate question in the way of the debug popup.
    boot(true, { enabled = true, side = 30, tilt = 20, crosshair = true, aim = 0 }, false,
        { enemies = "1", friends = "1", classColors = "1" })
    game.fire("PLAYER_ENTERING_WORLD"); frame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    frame(); frame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    eq(GamepadCameraOffsetDebugDB.runs[1].stopped, "combat")
    eq(describeSavedSettings(), "true 30 20 true 0")
    eq(popup(), nil, "no popup in combat")
    runUntilNoTimersLeft()
    eq(#GamepadCameraOffsetDebugDB.runs, 1, "nothing ran after the stop")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    eq(popup() ~= nil, true, "shown once the fight is over")
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
    -- The whole line: the packager takes anything after the name (a comment too) as part of it.
    assert(packageRules:find("\n  %- Debug%.lua\n"), ".pkgmeta ignores Debug.lua, alone on its line")
    local releaseToc = readFile("GamepadCameraOffset.toc"):gsub("\r", "")
        :gsub("#@do%-not%-package@.-#@end%-do%-not%-package@\n?", "")   -- what the packager does
    local loadedFiles = {}
    for line in releaseToc:gmatch("[^\n]+") do
        if not line:find("^#") then loadedFiles[#loadedFiles + 1] = line end
    end
    eq(table.concat(loadedFiles, ","), "GamepadCameraOffset.lua,Popup.lua,Nameplates.lua,RelatedAddon.lua", "the release .toc loads the addon's files, no Debug.lua")
end)

test("listed under Gamepad in the AddOns list, the game's own word", function()
    local file = assert(io.open("GamepadCameraOffset.toc")); local toc = file:read("*a"); file:close()
    eq(toc:match("## Category: ([^\r\n]+)"), "Gamepad")
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
