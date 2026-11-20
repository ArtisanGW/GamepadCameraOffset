-- Hints on the settings page for our other controller addons: a "Get" button
-- for each one that isn't installed. Its popup (Popup.lua) shows the download
-- link selected to copy (the game can't open a web page) and a Reload for once
-- it's installed. The other addons are named here only as text: nothing calls
-- them or depends on them.
-- "Crosshair on your target" was part of this addon until 1.7.0: if you had it
-- on, the Gamepad Reticle On Target popup opens once at login to say where it went.
local Camera = _G.GamepadCameraOffset

local RelatedAddons = {
    -- Each: its folder name, its title, its CurseForge page (the project's
    -- permanent short address, which redirects to it) and its button's tooltip.
    SIBLINGS = {
        {
            NAME = "GamepadReticleOnTarget",
            TITLE = "Gamepad Reticle On Target",
            LINK = "https://www.curseforge.com/projects/1819101",
            TOOLTIP = "Puts the controller's reticle just below your target's nameplate.\n\n"
            .. "It was \"Crosshair on your target\" here before 1.7.0.\n\n"
            .. "A separate addon; this one works without it.",
        },
        {
            NAME = "GamepadReticleCustomizer",
            TITLE = "Gamepad Reticle Customizer",
            LINK = "https://www.curseforge.com/projects/1818557",
            TOOLTIP = "Customizes the reticle:\n\n"
            .. "• Its shape, size, color and border\n"
            .. "• An icon on your target: its class, a raid marker\n\n"
            .. "A separate addon; this one works without it.",
        },
    },
}
Camera.RelatedAddons = RelatedAddons

-- Whether a sibling is turned off for this character in the AddOns list: first
-- whether it can load (GetAddOnInfo's reason "DISABLED"), then its switch for
-- this character (GetAddOnEnableState, 0 = off; the character is its GUID, as
-- the game's AddOns list uses).
function RelatedAddons.TurnedOff(sibling)
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" then return false end
    if type(addOns.GetAddOnInfo) == "function" then
        local succeeded, _, _, _, _, reason = pcall(addOns.GetAddOnInfo, sibling.NAME)
        if succeeded and reason == "DISABLED" then return true end
    end
    if type(addOns.GetAddOnEnableState) == "function" then
        local character = type(UnitGUID) == "function" and UnitGUID("player") or nil
        local succeeded, state = pcall(addOns.GetAddOnEnableState, sibling.NAME, character)
        if succeeded and tonumber(state) == 0 then return true end
    end
    return false
end

-- Whether a sibling is installed. Debug.lua (never in the release) sets
-- RelatedAddons.countTurnedOffAsMissing, so turning one off in the AddOns list
-- shows what players without it see: its button and popup.
function RelatedAddons.Installed(sibling)
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, sibling.NAME)
    if not (succeeded and exists == true) then return false end
    return not (RelatedAddons.countTurnedOffAsMissing and RelatedAddons.TurnedOff(sibling))
end

-- The siblings that aren't installed, in order.
function RelatedAddons.Missing()
    local missing = {}
    for _, sibling in ipairs(RelatedAddons.SIBLINGS) do
        if not RelatedAddons.Installed(sibling) then missing[#missing + 1] = sibling end
    end
    return missing
end

-- A sibling by its folder name.
function RelatedAddons.Sibling(name)
    for _, sibling in ipairs(RelatedAddons.SIBLINGS) do
        if sibling.NAME == name then return sibling end
    end
end

-- Its link to copy, and a Reload for once it's installed (Popup.lua).
-- intro (optional): a first paragraph.
function RelatedAddons.ShowLink(sibling, intro)
    Camera.Popup.Show({
        text = (intro or "") .. "To get " .. sibling.TITLE .. ":\n"
            .. "• Copy the link (Ctrl+C)\n"
            .. "• Install it\n"
            .. "• Reload",
        copyText = sibling.LINK,
        buttons = { { text = "Reload", reload = true }, { text = "Close" } },
    })
end

-- The settings page's buttons (GamepadCameraOffset.lua calls this while building it).
function Camera.AddRelatedAddonButtons(layout)
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    for _, sibling in ipairs(RelatedAddons.Missing()) do
        layout:AddInitializer(CreateSettingsButtonInitializer(sibling.TITLE, "Get " .. sibling.TITLE,
            function() RelatedAddons.ShowLink(sibling) end, sibling.TOOLTIP, true))
    end
end

-- Once, at the first login after the update, for those who had it on.
RelatedAddons.eventFrame = CreateFrame("Frame")
RelatedAddons.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
RelatedAddons.eventFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    local reticleAddon = RelatedAddons.Sibling("GamepadReticleOnTarget")
    if not Camera.reticleMoved or RelatedAddons.Installed(reticleAddon) then return end
    Camera.reticleMoved = nil
    RelatedAddons.ShowLink(reticleAddon, "Gamepad Camera Offset\n\n\"Crosshair on your target\" is now its own addon, "
        .. reticleAddon.TITLE .. ". The camera settings stay here.\n\n")
end)
