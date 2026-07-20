local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local TEMPLATES = require "widgets/redux/templates"

local CheckClientMod = Class(Screen, function(self, owner)
    Screen._ctor(self, "CheckClientMod")
    self.owner = owner

    self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self:SetMaxPropUpscale(MAX_HUD_SCALE)
    self:SetPosition(0, 0, 0)
    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetHAnchor(ANCHOR_LEFT)

    self.isopen = true
    self.scalingroot = self:AddChild(Widget("checkclientmodscalingroot"))
    self.scalingroot:SetScale(TheFrontEnd:GetHUDScale())

    self.root = self.scalingroot:AddChild(TEMPLATES.ScreenRoot("root"))

    local base_size = 128
    local cell_size = 73
    local row_w = cell_size
    local row_h = cell_size;
    local reward_width = 80
    local row_spacing = 5

    self.panel = self.root:AddChild(TEMPLATES.CurlyWindow(500, 150, TUNING.CHECKCLIENTMOD_TITLE, {
        {
            text = STRINGS.UI.SERVERLISTINGSCREEN.CONTINUE or "OK",
            cb = function()
                TheFrontEnd:PopScreen()
            end
        }
    }, nil, TUNING.CHECKCLIENTMOD_BODY))

end)

return CheckClientMod
