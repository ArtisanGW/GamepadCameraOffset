-- A hint on the settings page: Gamepad Crosshair Customizer, a separate addon,
-- customizes the controller's crosshair (shape, size, color, border, an icon on
-- your target). Shown only when it isn't installed; its button opens a box with
-- the download link selected to copy (the game can't open a web page). The other
-- addon is named here only as text: nothing calls it or depends on it.
local Camera = _G.GamepadCameraOffset

local RelatedAddon = {
    NAME = "GamepadCrosshairCustomizer",
    TITLE = "Gamepad Crosshair Customizer",
    -- CurseForge's permanent short address for its project (redirects to its page).
    LINK = "https://www.curseforge.com/projects/1818557",
}
Camera.RelatedAddon = RelatedAddon

function RelatedAddon.Installed()
    local addOns = _G.C_AddOns
    if type(addOns) ~= "table" or type(addOns.DoesAddOnExist) ~= "function" then return false end
    local succeeded, exists = pcall(addOns.DoesAddOnExist, RelatedAddon.NAME)
    return succeeded and exists == true
end

local box

local function buildBox()
    box = CreateFrame("Frame", "GamepadCameraOffsetLinkBox", UIParent)
    box:SetSize(460, 110)
    box:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    box:SetFrameStrata("DIALOG")
    box:EnableMouse(true)
    local background = box:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.85)
    box.text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.text:SetPoint("TOP", box, "TOP", 0, -14)
    box.text:SetWidth(430)
    box.editBox = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    box.editBox:SetSize(410, 24)
    box.editBox:SetPoint("TOP", box.text, "BOTTOM", 0, -10)
    box.editBox:SetAutoFocus(false)
    box.editBox:SetScript("OnEscapePressed", function() box:Hide() end)
    box.closeButton = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    box.closeButton:SetSize(130, 24)
    box.closeButton:SetPoint("BOTTOM", box, "BOTTOM", 0, 12)
    box.closeButton:SetText(CLOSE or "Close")
    box.closeButton:SetScript("OnClick", function() box:Hide() end)
    RelatedAddon.box = box
end

function RelatedAddon.ShowLink()
    if not box then buildBox() end
    box.text:SetText(RelatedAddon.TITLE .. ": copy the link with Ctrl+C, install it, then restart the game.")
    box.editBox:SetText(RelatedAddon.LINK)
    box:Show()
    box.editBox:SetFocus()
    box.editBox:HighlightText()
end

-- The settings page's button (GamepadCameraOffset.lua calls this while building it).
function Camera.AddRelatedAddonButton(layout)
    if RelatedAddon.Installed() then return end
    if not (layout and type(CreateSettingsButtonInitializer) == "function") then return end
    layout:AddInitializer(CreateSettingsButtonInitializer(RelatedAddon.TITLE, "Get " .. RelatedAddon.TITLE .. "...",
        function() RelatedAddon.ShowLink() end,
        "To customize the controller's crosshair: its shape, size, color and border, and an icon on your target "
        .. "(a player's class, a raid marker). A separate addon; this one works without it.", true))
end
