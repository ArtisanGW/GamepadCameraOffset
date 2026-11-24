-- GamepadCameraOffset against a fake game: CVars with the temp layer, the Settings API,
-- frames, timers and events. From GamepadCameraOffset:  luajit tests/run.lua
local reportLine = print   -- the tests replace print to read what the addon says
local failed, passed = 0, 0
local function test(name, testBody)
    local ok, err = xpcall(testBody, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; reportLine("FAIL " .. name .. "\n" .. err) end
end
local function expectEqual(actual, expected, message)
    if actual ~= expected then error((message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local game
-- releaseBuild: as in the release zip, without Debug.lua (see .pkgmeta).
-- nameplateOptions: { enemies, friends, classColors } as "0"/"1" (default all "0"),
-- refuse = true: the game won't take a change to them.
local function boot(gamepad, saved, releaseBuild, nameplateOptions)
    nameplateOptions = nameplateOptions or {}
    _G.C_AddOns = {
        DoesAddOnExist = function(name)
            return name == "GamepadReticleOnTarget" and (nameplateOptions.reticleAddonInstalled == true or nameplateOptions.reticleAddonOff == true)
        end,
        -- Turned off for this character (its GUID): the switch reads 0.
        GetAddOnEnableState = function(name, character)
            if name == "GamepadReticleOnTarget" and nameplateOptions.reticleAddonOff and character == "Player-93-0A1B2C3D" then return 0 end
            return 2
        end,
    }
    _G.UnitGUID = function(unit) if unit == "player" then return "Player-93-0A1B2C3D" end end
    game = { saved = {}, temp = {}, timers = {}, frames = {}, settings = {}, callbacks = {}, events = 0 }
    local defaults = { test_cameraOverShoulder = "0", test_cameraDynamicPitch = "0",
        test_cameraDynamicPitchBaseFovPad = "0.4", test_cameraDynamicPitchBaseFovPadFlying = "0.75",
        test_cameraDynamicPitchBaseFovPadDownScale = "0.25",
        CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "0" }
    for key, value in pairs(defaults) do game.saved[key] = value end
    game.saved.nameplateShowEnemies = nameplateOptions.enemies or "0"
    game.saved.nameplateShowFriendlyPlayers = nameplateOptions.friends or "0"
    game.saved.nameplateShowFriendlyClassColor = nameplateOptions.classColors or "0"
    local function fire(event, ...)
        for _, fakeFrame in ipairs(game.frames) do if fakeFrame.ev[event] and fakeFrame.script then fakeFrame.script(fakeFrame, event, ...) end end
    end
    game.fire = fire
    local function changed(cvarName) fire("CVAR_UPDATE", cvarName, _G.C_CVar.GetCVar(cvarName)) end
    if gamepad then game.temp.CameraKeepCharacterCentered = "1"; game.temp.CameraReduceUnexpectedMovement = "0" end
    _G.C_CVar = {
        GetCVar = function(cvarName) if game.temp[cvarName] ~= nil then return game.temp[cvarName] end return game.saved[cvarName] end,
        SetCVar = function(cvarName, value)
            if nameplateOptions.refuse and cvarName:find("^nameplate") then return false end
            game.saved[cvarName] = value; changed(cvarName); return true
        end,
        SetTempCVar = function(cvarName, value) game.temp[cvarName] = value; changed(cvarName) end,
        RemoveTempCVar = function(cvarName) game.temp[cvarName] = nil; changed(cvarName) end,
        GetCVarDefault = function(cvarName) return defaults[cvarName] end,
    }
    _G.InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
    _G.C_Timer = { After = function(_, callback) game.timers[#game.timers + 1] = callback end }
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
        function fakeRegion:SetAtlas(atlas) self.atlas = atlas end
        function fakeRegion:Show() self.shown = true end
        function fakeRegion:Hide() self.shown = false end
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
            self.scripts = self.scripts or {}
            self.scripts[scriptType] = handler
            if scriptType:find("^OnGamePad") then return end
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
        -- Protected: blocked in combat, like the game's.
        function fakeFrame:EnableGamePadStick(enable)
            if game.combat then error("EnableGamePadStick blocked in combat") end
            self.takesStick = enable
        end
        function fakeFrame:EnableGamePadButton(enable)
            if game.combat then error("EnableGamePadButton blocked in combat") end
            self.takesButtons = enable
        end
        function fakeFrame:Click() if self.click then self.click(self) end end
        function fakeFrame:HookScript(scriptType, handler)
            self.hooks = self.hooks or {}
            self.hooks[scriptType] = handler
        end
        -- A secure click (SecureHandlerClickTemplate): its _onclick snippet run with
        -- the restricted environment's few functions, then the hook.
        function fakeFrame:SecureClick(down)
            local snippet = self.attributes and self.attributes._onclick
            if snippet then
                local handle = {
                    SetBindingClick = function(_, _, key, buttonName) game.bindings[key] = buttonName; game.bindingOwners[key] = self end,
                    ClearBindings = function() _G.ClearOverrideBindings(self) end,
                }
                local run = assert(loadstring("local self, button, down = ...\n" .. snippet))
                setfenv(run, { PlayerInCombat = function() return game.combat end })
                run(handle, "LeftButton", down)
            end
            if self.hooks and self.hooks.OnClick then self.hooks.OnClick(self, "LeftButton", down) end
        end
        game.frames[#game.frames + 1] = fakeFrame
        return fakeFrame
    end
    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number" },
        RegisterVerticalLayoutCategory = function(name)
            return { name = name, GetID = function() return 42 end }, { AddInitializer = function(_, initializer) game.buttons[#game.buttons + 1] = initializer end }
        end,
        RegisterAddOnSetting = function(category, variable, key, savedTable, kind, label, defaultValue)
            if savedTable[key] == nil then savedTable[key] = defaultValue end
            local setting = { variable = variable, key = key, tbl = savedTable }
            -- As the game's: saved in the table, then its callback.
            function setting:SetValue(value) self.tbl[self.key] = value; game.callbacks[self.variable](nil, self, value) end
            game.settings[variable] = setting
            return setting
        end,
        SetOnValueChangedCallback = function(variable, callback) game.callbacks[variable] = callback end,
        CreateColorSwatch = function(_, setting) game.swatch = setting end,
        RegisterProxySetting = function(category, variable, kind, label, defaultValue, getValue, setValue)
            local s = { variable = variable, key = variable, label = label, getValue = getValue, setValue = setValue }
            game.settings[variable] = s
            return s
        end,
        CreateCheckbox = function() end,
        CreateSlider = function(_, setting, options) game.options = game.options or {}; game.options[setting.key] = options end,
        CreateSliderOptions = function(minimum, maximum, step)
            return { lo = minimum, hi = maximum, SetLabelFormatter = function(self, _, formatter) self.format = formatter end }
        end,
        RegisterAddOnCategory = function(category) game.category = category end,
        OpenToCategory = function(id) game.opened = id end,
    }
    _G.SlashCmdList = {}
    _G.UIParent = { GetHeight = function() return 768 end, GetEffectiveScale = function() return 2 end }
    game.cursorX = 500
    _G.GetCursorPosition = function() return game.cursorX, 300 end
    _G.GetScreenWidth = function() return 1000 end   -- 2000 pixels at scale 2
    game.zoom = 10
    _G.GetCameraZoom = function() return game.zoom end
    _G.GetCursorCenterPosition = function() return 0, 480 end
    _G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    _G.hooksecurefunc = function(owner, methodName, hook)
        if type(owner) == "string" then owner, methodName, hook = _G, owner, methodName end   -- the global form: hooksecurefunc("Name", fn)
        local original = owner[methodName]; owner[methodName] = function(...) local result = original(...); hook(...); return result end
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
        SetPoint = function(self, point, relativeFrame, relativePoint, x, y) self.point = { point, relativePoint, x, y, relativeTo = relativeFrame } end,
        -- Like the game: anchored to a nameplate (a restricted region), it can't be measured.
        GetPoint = function(self)
            local anchor = self.point
            if anchor and type(anchor.relativeTo) == "table" and anchor.relativeTo.restricted then
                error("GamepadReticle:GetPoint(): Action[FrameMeasurement] failed because[Can't measure restricted regions]")
            end
            if anchor then return anchor[1], anchor.relativeTo or UIParent, anchor[2], anchor[3], anchor[4] end
        end,
        Recenter = function(self) game.recenters = game.recenters + 1; self.point = { "CENTER", "BOTTOM", 0, 320 } end,
        Icons = { StandardIcon = { color = { 1, 1, 1, 1 }, SetVertexColor = function(self, red, green, blue, alpha) self.color = { red, green, blue, alpha } end } },
    }
    -- Units and their nameplates: game.units[unit] = true, game.nameplates[unit] = a frame.
    game.units, game.nameplates = {}, {}
    _G.UnitExists = function(unit) return game.units[unit] == true end
    _G.GetPhysicalScreenSize = function() return 2304, 1536 end
    game.buttons = {}
    _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, addSearchTags, newTagID, gameDataFunc, gameDataEvent)
        local initializer = { name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip,
            shownPredicates = {} }
        function initializer:AddShownPredicate(predicate) table.insert(self.shownPredicates, predicate) end
        -- As the game lays out the page: the row shows only if every shown predicate says so.
        function initializer:Shown()
            for _, predicate in ipairs(self.shownPredicates) do if not predicate() then return false end end
            return true
        end
        return initializer
    end
    local function addInitializer(_, initializer) game.buttons[#game.buttons + 1] = initializer end
    _G.SettingsPanel = { GetLayout = function() return { AddInitializer = addInitializer } end }
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit) return game.nameplates[unit] end }
    game.combat = false
    _G.InCombatLockdown = function() return game.combat end
    game.bindings, game.bindingOwners = {}, {}
    game.dragKeys = { "BUTTON3" }
    _G.GetBindingKey = function() return unpack(game.dragKeys) end
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
    _G.print = function(text) printed[#printed + 1] = text end
    local namespace = {}
    assert(loadfile("GamepadCameraOffset.lua"))("GamepadCameraOffset", namespace)
    assert(loadfile("CenterStop.lua"))("GamepadCameraOffset", namespace)
    assert(loadfile("OffsetKeys.lua"))("GamepadCameraOffset", namespace)
    assert(loadfile("CombatDPad.lua"))("GamepadCameraOffset", namespace)
    assert(loadfile("Popup.lua"))("GamepadCameraOffset", namespace)
    assert(loadfile("RelatedAddons.lua"))("GamepadCameraOffset", namespace)
    if not releaseBuild then assert(loadfile("Debug.lua"))("GamepadCameraOffset", namespace) end
    fire("ADDON_LOADED", "GamepadCameraOffset")
end
local function runNextFrame() local dueTimers = game.timers; game.timers = {}; for _, timer in ipairs(dueTimers) do timer() end end
local function set(key, value)
    local setting = game.settings["GamepadCameraOffset_" .. key]
    setting.tbl[setting.key] = value
    game.callbacks[setting.variable](nil, setting, value)
end
local get = function(cvarName) return C_CVar.GetCVar(cvarName) end

-- Settings that move the camera (the defaults are the game's own, which change nothing).
local function moved() return { enabled = true, side = 40, tilt = 50, lookDown = 50 } end

test("registers its page under Options > AddOns, with the game's own values as defaults", function()
    boot(true, nil)
    expectEqual(game.category.name, "Gamepad Camera Offset", "spaced in the settings window")
    expectEqual(GamepadCameraOffsetDB.enabled, true); expectEqual(GamepadCameraOffsetDB.side, 0); expectEqual(GamepadCameraOffsetDB.tilt, 0)
    expectEqual(GamepadCameraOffsetDB.lookDown, 0, "Default: the game's own")
    expectEqual(GamepadCameraOffsetDB.dragSpeed, 100, "Drag speed: Normal")
    expectEqual(game.options.side.format(40), "40% right"); expectEqual(game.options.side.format(-25), "25% left"); expectEqual(game.options.side.format(0), "Centered")
    expectEqual(game.options.tilt.format(35), "35% tilt"); expectEqual(game.options.tilt.format(0), "Off")
    expectEqual(game.options.aim, nil, "no reticle offset here any more")
    expectEqual(game.settings.GamepadCameraOffset_crosshair, nil, "no reticle setting either")
    expectEqual(SLASH_GAMEPADCAMERAOFFSET1, "/gpco"); expectEqual(SLASH_GAMEPADCAMERAOFFSET2, "/gamepadcameraoffset")
    SlashCmdList.GAMEPADCAMERAOFFSET("")
    expectEqual(game.opened, 42, "/gpco opens it")
end)

test("with the defaults (the game's values), the game's camera is left alone: no ActionCam, still centered", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    expectEqual(#game.consoleCommands, 0, "no ActionCam command")
    expectEqual(get("CameraKeepCharacterCentered"), "1", "the controller's own centering kept")
    expectEqual(get("test_cameraOverShoulder"), "0")
    set("side", 20)
    expectEqual(get("CameraKeepCharacterCentered"), "0", "a slider moved: now it applies")
    expectEqual(table.concat(game.consoleCommands, ","), "ActionCam basic")
    set("side", 0)
    expectEqual(get("CameraKeepCharacterCentered"), "1", "back at the game's values: the game's camera back")
    expectEqual(table.concat(game.consoleCommands, ","), "ActionCam basic,ActionCam off")
end)

test("on a controller, entering the world un-centers the camera and sets both offsets", function()
    boot(true, moved())
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    expectEqual(get("CameraKeepCharacterCentered"), "0", "the temp value wins over the controller's")
    expectEqual(game.saved.CameraKeepCharacterCentered, "1", "your saved setting untouched")
    expectEqual(get("test_cameraOverShoulder"), "1.2")
    expectEqual(get("test_cameraDynamicPitch"), "1")
    expectEqual(get("test_cameraDynamicPitchBaseFovPad"), "0.4375", "tilt 50%: halfway from 0.75 to 0.125")
    expectEqual(get("test_cameraDynamicPitchBaseFovPadFlying"), "0.4375")
    expectEqual(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.5", "tilt when looking down: 50% by default")
end)

test("ActionCam basic runs once before the first apply; off when disabled, basic again when enabled", function()
    boot(false, nil)
    expectEqual(#game.consoleCommands, 0, "nothing before entering the world")
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    set("side", 20); set("tilt", 70)
    expectEqual(table.concat(game.consoleCommands, ","), "ActionCam basic", "once, however many changes")
    set("enabled", false)
    expectEqual(table.concat(game.consoleCommands, ","), "ActionCam basic,ActionCam off")
    set("enabled", true)
    expectEqual(table.concat(game.consoleCommands, ","), "ActionCam basic,ActionCam off,ActionCam basic")
end)

test("disabled at login runs no ActionCam command", function()
    boot(false, { enabled = false })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    expectEqual(#game.consoleCommands, 0)
end)

test("the game's experimental warning: its event dropped at load, the popup hidden if shown", function()
    boot(false, nil)
    expectEqual(game.internalEvents.EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED, nil, "the game no longer listens for it")
    StaticPopup_Show("EXPERIMENTAL_CVAR_WARNING")
    expectEqual(game.popupsShown.EXPERIMENTAL_CVAR_WARNING, nil, "hidden at once")
    StaticPopup_Show("SOMETHING_ELSE")
    expectEqual(game.popupsShown.SOMETHING_ELSE, true, "other popups untouched")
end)

test("tilt when looking down: the slider's percentage as the game's 0 to 1, labelled", function()
    boot(false, moved())
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    set("lookDown", 80)
    expectEqual(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.8")
    set("lookDown", 500)
    expectEqual(get("test_cameraDynamicPitchBaseFovPadDownScale"), "1", "clamped")
    expectEqual(game.options.lookDown.format(80), "80% kept"); expectEqual(game.options.lookDown.format(0), "Default")
    set("lookDown", 0)
    expectEqual(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.25", "Default: the game's own value")
    set("enabled", false)
    expectEqual(get("test_cameraDynamicPitchBaseFovPadDownScale"), "0.25", "the game's default back")
end)

test("the game re-centering (a switch to the controller) is undone on the next frame, once", function()
    boot(true, moved())
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    C_CVar.SetTempCVar("CameraKeepCharacterCentered", "1")
    expectEqual(#game.timers, 1, "one re-apply queued")
    runNextFrame()
    expectEqual(get("CameraKeepCharacterCentered"), "0")
    expectEqual(#game.timers, 0, "its own change queues nothing more")
end)

test("sliders apply at once; tilt Off turns the pitch off", function()
    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    set("side", -50)
    expectEqual(get("test_cameraOverShoulder"), "-1.5", "50% left")
    set("tilt", 0)
    expectEqual(get("test_cameraDynamicPitch"), "0")
    set("side", 999)
    expectEqual(get("test_cameraOverShoulder"), "3", "clamped")
end)

-- The updater frame of OffsetKeys.lua: its OnUpdate run once, elapsed seconds later.
local function tick(elapsed)
    for _, fakeFrame in ipairs(game.frames) do
        if fakeFrame.update and fakeFrame.shown then fakeFrame.update(fakeFrame, elapsed) end
    end
end

test("keys move the side offset: in Key Bindings > AddOns, none bound", function()
    local bindings = assert(io.open("Bindings.xml")):read("*a")
    for _, name in ipairs({ "DRAG", "LEFT", "RIGHT" }) do
        assert(bindings:find('name="GAMEPADCAMERAOFFSET_' .. name .. '" category="ADDONS" runOnUp="true"', 1, true), name)
    end
    assert(not bindings:find("default="), "no key bound by default")
    boot(false, nil)
    expectEqual(BINDING_NAME_GAMEPADCAMERAOFFSET_DRAG, "Camera side: hold & drag")
end)

test("held drag key: moving the mouse moves the slider, the whole screen its whole range", function()
    boot(false, { enabled = true, side = 0, tilt = 0, lookDown = 0 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    keys.Drag("down")
    game.cursorX = 500 + 500   -- a quarter of the 2000-pixel screen to the right
    tick(0.016)
    expectEqual(GamepadCameraOffsetDB.side, 50, "saved through the slider's setting")
    expectEqual(get("test_cameraOverShoulder"), "1.5", "the camera follows")
    game.cursorX = 500 - 2000
    tick(0.016)
    expectEqual(GamepadCameraOffsetDB.side, -100, "clamped")
    keys.Drag("up")
    game.cursorX = 500
    tick(0.016)
    expectEqual(GamepadCameraOffsetDB.side, -100, "let go: stays")
end)

test("drag speed: 200% moves the slider twice as far for the same cursor move", function()
    boot(false, { enabled = true, side = 0, tilt = 0, lookDown = 0, dragSpeed = 200 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    keys.Drag("down")
    game.cursorX = 500 + 250   -- an eighth of the 2000-pixel screen
    tick(0.016)
    expectEqual(GamepadCameraOffsetDB.side, 50, "a quarter of the range at Normal would be 25")
    keys.Drag("up")
    expectEqual(game.options.dragSpeed.format(100), "Normal"); expectEqual(game.options.dragSpeed.format(250), "250%")
    expectEqual(GamepadCameraOffsetDB.dragSpeed, 200)
end)

test("in a fight: holding hold & drag turns the D-pad into steps, letting go gives it back", function()
    boot(true, { enabled = true, side = 0, tilt = 0, lookDown = 0, stepSize = 10 })
    game.fire("PLAYER_LOGIN"); game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local combatDPad = GamepadCameraOffset.CombatDPad
    expectEqual(game.bindings.BUTTON3, "GamepadCameraOffsetSecureDrag", "the hold & drag key goes through the secure button")
    game.combat = true
    combatDPad.dragButton:SecureClick(true)
    expectEqual(game.bindings.PADDRIGHT, "GamepadCameraOffsetStepRight", "D-pad right: a step")
    _G.GamepadCameraOffsetStepRight.click(nil, "LeftButton", true)
    expectEqual(GamepadCameraOffsetDB.side, 10, "stepped in combat")
    _G.GamepadCameraOffsetStepRight.click(nil, "LeftButton", false)
    _G.GamepadCameraOffsetStepLeft.click(nil, "LeftButton", true)
    _G.GamepadCameraOffsetStepLeft.click(nil, "LeftButton", false)
    expectEqual(GamepadCameraOffsetDB.side, 0, "and back")
    combatDPad.dragButton:SecureClick(false)
    expectEqual(game.bindings.PADDRIGHT, nil, "let go: the D-pad is the game's again")
    expectEqual(game.bindings.BUTTON3, "GamepadCameraOffsetSecureDrag", "the key's route stays")
    game.combat = false
end)

test("out of a fight the secure button leaves the D-pad alone (OffsetKeys takes it)", function()
    boot(true, { enabled = true, side = 0, tilt = 0, lookDown = 0 })
    game.fire("PLAYER_LOGIN"); game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    GamepadCameraOffset.CombatDPad.dragButton:SecureClick(true)
    expectEqual(game.bindings.PADDRIGHT, nil)
    GamepadCameraOffset.CombatDPad.dragButton:SecureClick(false)
end)

test("step size: a slider, 20% until changed", function()
    boot(false, { enabled = true, side = 0, tilt = 0, lookDown = 0 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    expectEqual(GamepadCameraOffsetDB.stepSize, 20, "default")
    keys.Step(1, "down"); keys.Step(1, "up")
    expectEqual(GamepadCameraOffsetDB.side, 20, "a 20% step")
    set("stepSize", 35)
    keys.Step(1, "down"); keys.Step(1, "up")
    expectEqual(GamepadCameraOffsetDB.side, 35, "onto the 35% steps")
    expectEqual(game.options.stepSize.format(35), "35%")
end)

test("a Key Bindings button: opens the game's page at AddOns, that section opened up", function()
    local addonsSection = { GetName = function() return "AddOns" end, data = {} }
    local opened
    _G.ADDONS = "AddOns"
    boot(false, nil)
    Settings.KEYBINDINGS_CATEGORY_ID = 7
    Settings.OpenToCategory = function(id, section) opened = { id, section } end
    _G.SettingsPanel.GetCategory = function(_, id) return id == 7 and "keys" or nil end
    _G.SettingsPanel.GetLayout = function(_, category)
        if category == "keys" then return { EnumerateInitializers = function() return ipairs({ addonsSection }) end } end
        return { AddInitializer = function(_, initializer) game.buttons[#game.buttons + 1] = initializer end }
    end
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Side offset keys" then button = initializer end end
    assert(button, "the button is on the page")
    expectEqual(button.buttonText, "Key Bindings")
    button.onClick()
    expectEqual(opened[1], 7); expectEqual(opened[2], "AddOns")
    expectEqual(addonsSection.data.expanded, true)
end)

-- The frame that takes the controller while Hold & drag is held.
local function controllerTaker()
    for _, fakeFrame in ipairs(game.frames) do
        if fakeFrame.scripts and fakeFrame.scripts.OnGamePadStick then return fakeFrame end
    end
end

test("hold & drag on a controller: the left stick and the D-pad move it, the stick taken from walking", function()
    boot(true, { enabled = true, side = 0, tilt = 0, lookDown = 0, stepSize = 10 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    local taker = controllerTaker()
    keys.Drag("down")
    expectEqual(taker.takesStick, true, "stick taken while held"); expectEqual(taker.takesButtons, true)
    expectEqual(taker.scripts.OnGamePadStick(taker, "Movement", 1, 0), false, "the left stick: used, not walked with")
    expectEqual(taker.scripts.OnGamePadStick(taker, "Camera", 1, 0), true, "the right stick: the game's")
    tick(0.25)
    expectEqual(GamepadCameraOffsetDB.side, 25, "pushed all the way: 100% a second")
    taker.scripts.OnGamePadStick(taker, "Movement", -0.5, 0)
    tick(0.1); tick(0.1)
    expectEqual(GamepadCameraOffsetDB.side, 15, "half-way left: slower, fractions kept")
    taker.scripts.OnGamePadStick(taker, "Movement", 0, 0)
    taker.scripts.OnGamePadButtonDown(taker, "PADDRIGHT")
    expectEqual(GamepadCameraOffsetDB.side, 20, "D-pad: a step")
    tick(0.5)
    expectEqual(GamepadCameraOffsetDB.side, 30, "held: repeats")
    taker.scripts.OnGamePadButtonUp(taker, "PADDRIGHT")
    tick(1)
    expectEqual(GamepadCameraOffsetDB.side, 30, "D-pad let go")
    expectEqual(taker.takesStick, true, "still held")
    taker.scripts.OnGamePadButtonUp(taker, "PADRSTICK")
    expectEqual(taker.takesStick, false, "the click let go: the controller is the game's again")
    expectEqual(taker.takesButtons, false)
    expectEqual(taker.shown, false)
end)

test("Stop at center on: hold & drag stops there for a moment, with a buzz on the controller", function()
    boot(true, { enabled = true, side = 30, tilt = 0, lookDown = 0, centerHold = true })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local vibrations = {}
    _G.C_GamePad = { SetVibration = function(kind) vibrations[#vibrations + 1] = kind end, StopVibration = function() end }
    local keys = GamepadCameraOffset.OffsetKeys
    local taker = controllerTaker()
    keys.Drag("down")
    taker.scripts.OnGamePadStick(taker, "Movement", -1, 0)
    tick(0.4)
    expectEqual(GamepadCameraOffsetDB.side, 0, "crossing the center: stops there")
    expectEqual(#vibrations, 1, "a buzz")
    tick(0.05)
    expectEqual(GamepadCameraOffsetDB.side, 0, "held a moment")
    tick(0.15)
    expectEqual(GamepadCameraOffsetDB.side, -5, "then on: 20% moved, 15% held")
    expectEqual(#vibrations, 1, "one buzz")
    keys.Drag("up")
    _G.C_GamePad = nil
end)

test("Stop at center: off until you turn it on, then a drag past the center stops there", function()
    boot(false, { enabled = true, side = 50, tilt = 0, lookDown = 0 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    expectEqual(GamepadCameraOffsetDB.centerHold, false, "off for new players")
    local keys = GamepadCameraOffset.OffsetKeys
    game.cursorX = 500
    keys.Drag("down")
    game.cursorX = 500 - 1000   -- half the screen left: 100%
    tick(0.016)
    expectEqual(GamepadCameraOffsetDB.side, -50, "off: straight through the center")
    keys.Drag("up")
    set("centerHold", true)
    game.cursorX = 500
    keys.Drag("down")
    game.cursorX = 500 + 1000
    tick(0.016)
    expectEqual(GamepadCameraOffsetDB.side, 0, "on: stops at the center")
    keys.Drag("up")
end)

test("hold & drag starting at the center leaves it at once", function()
    boot(true, { enabled = true, side = 0, tilt = 0, lookDown = 0 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    local taker = controllerTaker()
    keys.Drag("down")
    taker.scripts.OnGamePadStick(taker, "Movement", 1, 0)
    tick(0.1)
    expectEqual(GamepadCameraOffsetDB.side, 10)
    keys.Drag("up")
end)

test("drag speed: 300% makes the left stick three times faster", function()
    boot(true, { enabled = true, side = 0, tilt = 0, lookDown = 0, dragSpeed = 300 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    local taker = controllerTaker()
    keys.Drag("down")
    taker.scripts.OnGamePadStick(taker, "Movement", 1, 0)
    tick(0.25)
    expectEqual(GamepadCameraOffsetDB.side, 75, "25 at Normal")
    keys.Drag("up")
end)

test("hold & drag: in combat only the mouse; a fight starting gives the controller back", function()
    boot(true, { enabled = true, side = 0, tilt = 0, lookDown = 0 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    local taker = controllerTaker()
    keys.Drag("down")
    expectEqual(taker.takesStick, true)
    taker.script(taker, "PLAYER_REGEN_DISABLED")
    expectEqual(taker.takesStick, false, "given back before the lock")
    game.combat = true
    keys.Drag("down")
    expectEqual(taker.takesStick, false, "not taken in combat")
    game.cursorX = 500 + 200
    tick(0.016)
    expectEqual(GamepadCameraOffsetDB.side, 20, "the mouse still works")
    keys.Drag("up")
    expectEqual(taker.shown, false)
end)

test("left and right keys: a step each press, repeating while held, back onto the steps", function()
    boot(false, { enabled = true, side = 37, tilt = 0, lookDown = 0, stepSize = 10 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    local keys = GamepadCameraOffset.OffsetKeys
    keys.Step(1, "down")
    expectEqual(GamepadCameraOffsetDB.side, 40, "37 onto the next step")
    tick(0.3)
    expectEqual(GamepadCameraOffsetDB.side, 40, "not yet repeating")
    tick(0.2)
    expectEqual(GamepadCameraOffsetDB.side, 50, "held: repeats")
    tick(0.1)
    expectEqual(GamepadCameraOffsetDB.side, 60)
    keys.Step(1, "up")
    tick(1)
    expectEqual(GamepadCameraOffsetDB.side, 60, "let go: stops")
    keys.Step(-1, "down"); keys.Step(-1, "up")
    expectEqual(GamepadCameraOffsetDB.side, 50)
    GamepadCameraOffsetDB.side = 100
    keys.Step(1, "down"); keys.Step(1, "up")
    expectEqual(GamepadCameraOffsetDB.side, 100, "never past 100%")
end)

test("disabling puts the game's camera back: controller temp values, else none", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    set("enabled", false)
    expectEqual(get("test_cameraOverShoulder"), "0")
    expectEqual(get("test_cameraDynamicPitchBaseFovPad"), "0.4", "game default")
    expectEqual(game.temp.CameraKeepCharacterCentered, "1", "the controller's own value back")
    C_CVar.SetTempCVar("CameraKeepCharacterCentered", "1")
    expectEqual(#game.timers, 0, "disabled: the game's centering is left alone")

    boot(false, { enabled = true, side = 30, tilt = 20 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    set("enabled", false)
    expectEqual(game.temp.CameraKeepCharacterCentered, nil, "keyboard: no temp value left")
    expectEqual(get("CameraKeepCharacterCentered"), "1")
end)

test("disabled at login touches nothing", function()
    boot(true, { enabled = false, side = 30, tilt = 20 })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    expectEqual(get("test_cameraOverShoulder"), "0")
    expectEqual(game.temp.CameraKeepCharacterCentered, "1")
end)

local function near(actual, expected, message) if math.abs(actual - expected) > 0.01 then error((message or "") .. ": expected " .. expected .. ", got " .. actual, 2) end end

local function onUpdateFramesShown()
    local count = 0
    for _, fakeFrame in ipairs(game.frames) do if fakeFrame.update and fakeFrame.shown then count = count + 1 end end
    return count
end

test("no crosshair color here any more: the dot keeps its own, /gpco color opens the settings, 1.0's saved color dropped", function()
    boot(true, { crosshairColor = "FF3030FF" })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    expectEqual(GamepadCameraOffsetDB.crosshairColor, nil, "1.0's saved color dropped")
    local color = GamepadReticle.Icons.StandardIcon.color
    expectEqual(table.concat(color, " "), "1 1 1 1", "the dot's color untouched")
    expectEqual(game.swatch, nil, "no color swatch on the page")
    SlashCmdList.GAMEPADCAMERAOFFSET("color FF3030FF")
    expectEqual(game.opened, 42, "/gpco color: just the settings")
    expectEqual(table.concat(GamepadReticle.Icons.StandardIcon.color, " "), "1 1 1 1")
end)

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

test("the reticle isn't moved here any more: the game's own place, whatever the target", function()
    boot(true, nil)
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    game.units.target = true; game.nameplates.target = {}
    game.fire("PLAYER_TARGET_CHANGED"); runNextFrame()
    expectEqual(GamepadReticle.point, nil, "never touched")
    expectEqual(game.recenters, 0)
end)

test("without Gamepad Reticle On Target: a button shows its link to copy; with it, no button", function()
    boot(true, nil)
    local button
    for _, initializer in ipairs(game.buttons) do if initializer.name == "Reticle on your target" then button = initializer end end
    expectEqual(button and button.buttonText, "Get the addon")
    button.onClick()
    local box = popup()
    expectEqual(box.editBox:GetText(), "https://www.curseforge.com/projects/1819101")
    expectEqual(box.editBox.highlighted, true, "selected, ready for Ctrl+C")
    expectEqual(popupButtons(), "Close, [secure] Reload", "a Reload for once it's installed")
    clickPopup("Close")
    expectEqual(popup(), nil, "closed")
    boot(true, nil, false, { reticleAddonInstalled = true })
    for _, initializer in ipairs(game.buttons) do expectEqual(initializer.name ~= "Reticle on your target", true, "installed: no button") end
end)

test("settings left by earlier versions are dropped quietly: no popup, the camera settings kept", function()
    boot(true, { enabled = true, side = 30, crosshairColor = "FF3030FF", crosshair = true, aim = -5, nameplatesAsked = true })
    expectEqual(GamepadCameraOffsetDB.crosshair, nil); expectEqual(GamepadCameraOffsetDB.aim, nil); expectEqual(GamepadCameraOffsetDB.nameplatesAsked, nil)
    expectEqual(GamepadCameraOffsetDB.crosshairColor, nil)
    expectEqual(GamepadCameraOffsetDB.side, 30, "the camera settings kept")
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    expectEqual(popup(), nil, "nothing said")
end)

-- /gpco debug: the in-game suite, run here against the fake game.
local function runUntilNoTimersLeft()
    for _ = 1, 200 do if #game.timers == 0 then return end; runNextFrame() end
    error("the debug run never ended")
end
local function describeSavedSettings()
    local saved = GamepadCameraOffsetDB
    return string.format("%s %s %s", tostring(saved.enabled), saved.side, saved.tilt)
end

test("/gpco debug on a controller: every check passes, settings come back, findings saved", function()
    boot(true, { enabled = true, side = 30, tilt = 20 })
    game.fire("PLAYER_LOGIN"); game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    runUntilNoTimersLeft()
    local runs = GamepadCameraOffsetDebugDB.runs
    expectEqual(#runs, 1, "one run saved")
    local run = runs[1]
    for _, check in ipairs(run.checks) do
        if check.result ~= "pass" then
            error(check.result .. ": " .. check.name .. " expected " .. tostring(check.expected)
                .. " got " .. tostring(check.actual) .. " " .. tostring(check.note))
        end
    end
    expectEqual(run.failed, 0); expectEqual(run.skipped, 0); expectEqual(run.passed > 20, true, "passed " .. run.passed)
    expectEqual(run.environment.controllerUI, true); expectEqual(run.environment.build, "70959"); expectEqual(run.environment.settings.side, 30)
    expectEqual(describeSavedSettings(), "true 30 20", "your settings back")
    expectEqual(get("test_cameraOverShoulder"), "0.9", "and applied")
    expectEqual(GamepadCameraOffsetDebugDB.settingsToRestore, nil)
    local reloadBox = popup()
    expectEqual(reloadBox ~= nil, true, "reload popup shown")
    expectEqual(reloadBox.reloadButton.attributes.macrotext, "/reload"); expectEqual(reloadBox.reloadButton.template, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    expectEqual(popupButtons(), "Later, [secure] Reload")
    clickPopup("Later"); expectEqual(popup(), nil, "Later hides it")
end)

test("/gpco debug on keyboard: the controller checks skipped, the rest pass", function()
    boot(false, nil)
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    runUntilNoTimersLeft()
    local run = GamepadCameraOffsetDebugDB.runs[1]
    expectEqual(run.failed, 0); expectEqual(run.skipped > 0, true)
    for _, check in ipairs(run.checks) do
        if check.result == "skip" then expectEqual(check.note, "controller UI off") end
    end
end)

test("/gpco debug: a fight stops it, settings come back, the box waits for the fight's end", function()
    boot(true, { enabled = true, side = 30, tilt = 20 }, false,
        { enemies = "1", friends = "1", classColors = "1" })
    game.fire("PLAYER_ENTERING_WORLD"); runNextFrame()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    runNextFrame(); runNextFrame()
    game.combat = true
    game.fire("PLAYER_REGEN_DISABLED")
    expectEqual(GamepadCameraOffsetDebugDB.runs[1].stopped, "combat")
    expectEqual(describeSavedSettings(), "true 30 20")
    expectEqual(popup(), nil, "no popup in combat")
    runUntilNoTimersLeft()
    expectEqual(#GamepadCameraOffsetDebugDB.runs, 1, "nothing ran after the stop")
    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(popup() ~= nil, true, "shown once the fight is over")
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    expectEqual(#game.timers > 0, true, "and out of combat it runs again")
end)

test("/gpco debug: refused in combat; last and clear", function()
    boot(true, nil)
    game.combat = true
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    expectEqual(GamepadCameraOffsetDebugDB, nil, "nothing started, nothing saved")
    expectEqual(game.printed[#game.printed]:match("not in combat") ~= nil, true)
    game.combat = false
    SlashCmdList.GAMEPADCAMERAOFFSET("debug last")
    expectEqual(game.printed[#game.printed]:match("no saved run") ~= nil, true)
    SlashCmdList.GAMEPADCAMERAOFFSET("debug"); runUntilNoTimersLeft()
    SlashCmdList.GAMEPADCAMERAOFFSET("debug last")
    expectEqual(game.printed[#game.printed]:match("0 failed") ~= nil, true, game.printed[#game.printed])
    SlashCmdList.GAMEPADCAMERAOFFSET("debug clear")
    expectEqual(#GamepadCameraOffsetDebugDB.runs, 0)
    SlashCmdList.GAMEPADCAMERAOFFSET("")
    expectEqual(game.opened, 42, "plain /gpco still opens the settings")
end)

test("a reload in the middle of a run: your settings are back at the next login", function()
    boot(true, { enabled = true, side = -100, height = 0 })
    GamepadCameraOffsetDebugDB = { runs = {}, settingsToRestore = { enabled = true, side = 30, tilt = 20 } }
    game.fire("PLAYER_LOGIN")
    expectEqual(describeSavedSettings(), "true 30 20")
    expectEqual(GamepadCameraOffsetDebugDB.settingsToRestore, nil)
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
    expectEqual(table.concat(loadedFiles, ","), "GamepadCameraOffset.lua,CenterStop.lua,OffsetKeys.lua,CombatDPad.lua,Popup.lua,RelatedAddons.lua", "the release .toc loads the addon's files, no Debug.lua")
end)

test("listed under Gamepad in the AddOns list, the game's own word", function()
    local file = assert(io.open("GamepadCameraOffset.toc")); local toc = file:read("*a"); file:close()
    expectEqual(toc:match("## Category: ([^\r\n]+)"), "Gamepad")
end)

test("without Debug.lua (the release), the addon works and /gpco debug opens the settings", function()
    boot(true, moved(), true)
    expectEqual(GamepadCameraOffset.Debug, nil)
    game.fire("PLAYER_ENTERING_WORLD")
    runNextFrame()
    expectEqual(C_CVar.GetCVar("CameraKeepCharacterCentered"), "0", "the camera offset still applies")
    SlashCmdList.GAMEPADCAMERAOFFSET("debug")
    expectEqual(game.opened, 42, "/gpco debug opens the settings page")
end)

test("its icon in the AddOns list: Media/icon-64.png, shipped", function()
    local function readBytes(path) local file = assert(io.open(path, "rb")); local text = file:read("*a"); file:close(); return text end
    local toc = readBytes("GamepadCameraOffset.toc"):gsub("\r", "")
    expectEqual(toc:match("## IconTexture: ([^\n]+)"), "Interface\\AddOns\\GamepadCameraOffset\\Media\\icon-64.png")
    expectEqual(readBytes("Media/icon-64.png"):sub(2, 4), "PNG", "a PNG file")
    expectEqual(readBytes(".pkgmeta"):find("- Media/icon-64.png", 1, true), nil, "not left out of the release")
end)

test("debug build: Gamepad Reticle On Target turned off counts as missing, to see its button; the release doesn't", function()
    local function button()
        for _, initializer in ipairs(game.buttons) do if initializer.name == "Reticle on your target" then return initializer end end
    end
    boot(true, nil, false, { reticleAddonOff = true })
    expectEqual(button() ~= nil, true, "turned off for this character: the button, as players without it see it")
    boot(true, nil, true, { reticleAddonOff = true })
    expectEqual(button(), nil, "the release: installed is installed")
    boot(true, nil, false, { reticleAddonInstalled = true })
    expectEqual(button(), nil, "debug build, turned on: no button")
end)

test("a Get button for each missing sibling, in order after the Key Bindings one, each with its own CurseForge link", function()
    boot(true, nil)
    local names = {}
    for _, initializer in ipairs(game.buttons) do if initializer.buttonText then names[#names + 1] = initializer.name .. ": " .. initializer.buttonText end end
    expectEqual(table.concat(names, ", "), "Side offset keys: Key Bindings, Reticle on your target: Get the addon, Customize the reticle: Get the addon, Map without its hitch: Get the addon")
    for _, initializer in ipairs(game.buttons) do
        if initializer.name == "Customize the reticle" then initializer.onClick() end
    end
    expectEqual(_G.GamepadCameraOffsetPopup.editBox:GetText(), "https://www.curseforge.com/projects/1818557")
end)

test("saved keys the addon doesn't use are dropped, its settings kept", function()
    boot(true, { enabled = true, side = 30, height = 0, somethingElse = 1 })
    expectEqual(GamepadCameraOffsetDB.height, nil); expectEqual(GamepadCameraOffsetDB.somethingElse, nil); expectEqual(GamepadCameraOffsetDB.side, 30)
end)

reportLine(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
