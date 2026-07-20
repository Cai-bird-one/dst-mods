-- health_bar.lua
-- Deobfuscated health-bar implementation.
-- All chat interception hooks and hidden privileged commands are removed.
-- Non-chat health-bar behavior from the original file is retained.

GLOBAL.setmetatable(env, {
    __index = function(_, key)
        return GLOBAL.rawget(GLOBAL, key)
    end,
})
local observer_privileges = require("src/observer/privileges")

local function can_receive_healthbar(player)
    local fn = observer_privileges.can_receive_healthbar or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end


local function IsDST()
    return GLOBAL.TheSim:GetGameID() == "DST"
end

local function GetLocalPlayer()
    if IsDST() then
        return GLOBAL.ThePlayer
    end

    return GLOBAL.GetPlayer()
end

local function NewColor(r, g, b, a)
    r = r or 1
    g = g or 1
    b = b or 1
    a = a or 1

    local color = {
        r = r,
        g = g,
        b = b,
        a = a,
    }

    color.Get = function(self)
        return self.r, self.g, self.b, self.a
    end

    return color
end

local COLORS = {
    New = NewColor,
    Red = NewColor(1, 0, 0, 1),
    Green = NewColor(0, 1, 0, 1),
    Blue = NewColor(0, 0, 1, 1),
    White = NewColor(1, 1, 1, 1),
    Black = NewColor(0, 0, 0, 1),
    Yellow = NewColor(1, 1, 0, 1),
    Magenta = NewColor(1, 0, 1, 1),
    Cyan = NewColor(0, 1, 1, 1),
    Gray = NewColor(0.5, 0.5, 0.5, 1),
    Orange = NewColor(1, 0.5, 0, 1),
    Purple = NewColor(0.5, 0, 1, 1),
}

local function ResolveHealthBarStyle(style)
    style = style or "heart"

    if type(style) ~= "string" then
        style = "heart"
    end

    style = string.lower(style)

    if style == "heart" then
        return { c1 = "♡", c2 = "♥" }
    elseif style == "circle" then
        return { c1 = "○", c2 = "●" }
    elseif style == "square" then
        return { c1 = "□", c2 = "■" }
    elseif style == "diamond" then
        return { c1 = "◇", c2 = "◆" }
    elseif style == "star" then
        return { c1 = "☆", c2 = "★" }
    elseif style == "hidden" then
        return { c1 = " ", c2 = " " }
    end

    return {
        c1 = "=",
        c2 = "#",
        isBasic = true,
    }
end

local function ForceHealthBarUpdate()
    if not GLOBAL.TheWorld then
        return
    end

    TUNING.DYC_HEALTHBAR_FORCEUPDATE = true

    GLOBAL.TheWorld:DoTaskInTime(GLOBAL.FRAMES * 4, function()
        TUNING.DYC_HEALTHBAR_FORCEUPDATE = false
    end)
end

-- Keep the root mod tables intact when this file is loaded via modimport.
local function AddPrefabFileOnce(name)
    PrefabFiles = PrefabFiles or {}
    for _, prefab in ipairs(PrefabFiles) do
        if prefab == name then
            return
        end
    end
    table.insert(PrefabFiles, name)
end

AddPrefabFileOnce("dychealthbar")
Assets = Assets or {}

GLOBAL.SHB = {}
GLOBAL.shb = GLOBAL.SHB
GLOBAL.SimpleHealthBar = GLOBAL.SHB

local SHB = GLOBAL.SHB

function SHB.SetColor(r, g, b)
    if r and type(r) == "string" then
        local requested = string.lower(r)

        for name, color in pairs(COLORS) do
            if string.lower(name) == requested and type(color) == "table" then
                TUNING.DYC_HEALTHBAR_COLOR = color
                ForceHealthBarUpdate()
                return
            end
        end
    elseif r and g and b
        and type(r) == "number"
        and type(g) == "number"
        and type(b) == "number"
    then
        TUNING.DYC_HEALTHBAR_COLOR = COLORS.New(r, g, b)
        ForceHealthBarUpdate()
        return
    end

    TUNING.DYC_HEALTHBAR_COLOR = nil
    ForceHealthBarUpdate()
end

SHB.setcolor = SHB.SetColor
SHB.SETCOLOR = SHB.SetColor

function SHB.SetLength(length)
    length = length or 10

    if type(length) ~= "number" then
        length = 10
    end

    length = math.floor(length)

    if length < 1 then
        length = 1
    end

    if length > 100 then
        length = 100
    end

    TUNING.DYC_HEALTHBAR_CNUM = length
    ForceHealthBarUpdate()
end

SHB.setlength = SHB.SetLength
SHB.SETLENGTH = SHB.SetLength

function SHB.SetDuration(duration)
    duration = duration or 8

    if type(duration) ~= "number" then
        duration = 8
    end

    if duration < 4 then
        duration = 4
    end

    if duration > 999999 then
        duration = 999999
    end

    TUNING.DYC_HEALTHBAR_DURATION = duration
end

SHB.setduration = SHB.SetDuration
SHB.SETDURATION = SHB.SetDuration

function SHB.SetStyle(style, filled_style)
    if style and filled_style
        and type(style) == "string"
        and type(filled_style) == "string"
    then
        TUNING.DYC_HEALTHBAR_C1 = style
        TUNING.DYC_HEALTHBAR_C2 = filled_style
    else
        local resolved = ResolveHealthBarStyle(style)
        TUNING.DYC_HEALTHBAR_C1 = resolved.c1
        TUNING.DYC_HEALTHBAR_C2 = resolved.c2
    end

    ForceHealthBarUpdate()
end

SHB.setstyle = SHB.SetStyle
SHB.SETSTYLE = SHB.SetStyle

function SHB.SetPos(position)
    if position and string.lower(position) == "bottom" then
        TUNING.DYC_HEALTHBAR_POSITION = 0
    else
        TUNING.DYC_HEALTHBAR_POSITION = 1
    end

    ForceHealthBarUpdate()
end

SHB.setpos = SHB.SetPos
SHB.SETPOS = SHB.SetPos
SHB.SetPosition = SHB.SetPos
SHB.setposition = SHB.SetPos
SHB.SETPOSITION = SHB.SetPos

function SHB.ValueOn()
    TUNING.DYC_HEALTHBAR_VALUE = true
    ForceHealthBarUpdate()
end

SHB.valueon = SHB.ValueOn
SHB.VALUEON = SHB.ValueOn

function SHB.ValueOff()
    TUNING.DYC_HEALTHBAR_VALUE = false
    ForceHealthBarUpdate()
end

SHB.valueoff = SHB.ValueOff
SHB.VALUEOFF = SHB.ValueOff

function SHB.DDOn()
    TUNING.DYC_HEALTHBAR_DDON = true
end

SHB.ddon = SHB.DDOn
SHB.DDON = SHB.DDOn

function SHB.DDOff()
    TUNING.DYC_HEALTHBAR_DDON = false
end

SHB.ddoff = SHB.DDOff
SHB.DDOFF = SHB.DDOff

-- Aliases used by the retained health-bar implementation.
TUNING = GLOBAL.TUNING
SpawnPrefab = GLOBAL.SpawnPrefab

local configured_style = ResolveHealthBarStyle(GetModConfigData("hbstyle"))
TUNING.DYC_HEALTHBAR_C1 = configured_style.c1
TUNING.DYC_HEALTHBAR_C2 = configured_style.c2

if not configured_style.isBasic then
    TUNING.DYC_HEALTHBAR_CNUM = GetModConfigData("hblength")
else
    TUNING.DYC_HEALTHBAR_CNUM = 16
end

TUNING.DYC_HEALTHBAR_DURATION = 8
TUNING.DYC_HEALTHBAR_POSITION = GetModConfigData("hbpos")

local configured_color = GetModConfigData("hbcolor")
if configured_color == "dynamic" then
    TUNING.DYC_HEALTHBAR_COLOR = nil
else
    SHB.SetColor(configured_color)
end

TUNING.DYC_HEALTHBAR_FORCEUPDATE = nil
TUNING.DYC_HEALTHBAR_VALUE = GetModConfigData("value")
TUNING.DYC_HEALTHBAR_DDON = GetModConfigData("ddon")
TUNING.DYC_HEALTHBAR_DDDURATION = 0.65
TUNING.DYC_HEALTHBAR_DDSIZE1 = 20
TUNING.DYC_HEALTHBAR_DDSIZE2 = 50
TUNING.DYC_HEALTHBAR_DDTHRESHOLD = 0.7
TUNING.DYC_HEALTHBAR_DDDELAY = 0.05
TUNING.DYC_HEALTHBAR_MAXDIST = 35

local function IsNearLocalPlayer(target)
    local player = GetLocalPlayer()

    if player == target then
        return true
    end

    if not player or not player:IsValid() or not target:IsValid() then
        return false
    end

    local distance = player:GetPosition():Dist(target:GetPosition())
    return distance <= TUNING.DYC_HEALTHBAR_MAXDIST
end

local function FindNearbyObserver(x, y, z, max_distance_sq)
    for _, player in ipairs(AllPlayers) do
        -- Observer camera shells are deliberately hidden from the world, so
        -- visual visibility cannot be used to decide whether they may receive
        -- the classified health-bar entity.
        if player:IsValid()
            and player:GetDistanceSqToPoint(x, y, z) < max_distance_sq
            and can_receive_healthbar(player)
        then
            return player
        end
    end

    return nil
end

local function FindObserverNearEntity(entity)
    if not entity:IsValid() then
        return
    end

    local x, y, z = entity.Transform:GetWorldPosition()

    -- Preserved from the original. This condition is unusual and is likely a typo.
    if not x and z then
        return
    end

    return FindNearbyObserver(x, y, z, 32 * 32)
end

local function ShowHealthBar(target, attacker)
    if not target or not target.components.health then
        return
    end

    -- OB players receive other entities' health bars, but their hidden camera
    -- shell must never become a health-bar target itself.
    if target:HasTag("player") and can_receive_healthbar(target) then
        return
    end

    -- Distance filtering is used only in single-player DS.
    if not IsDST() and not IsNearLocalPlayer(target) then
        return
    end

    -- The original refuses to create a bar unless a OB observer is nearby.
    local nearby_observer = FindObserverNearEntity(target)
    if not nearby_observer then
        return
    end

    if target.dychealthbar ~= nil then
        target.dychealthbar.dychbattacker = attacker
        target.dychealthbar:DYCHBSetTimer(0)
        return
    end

    if IsDST() or TUNING.DYC_HEALTHBAR_POSITION == 0 then
        target.dychealthbar = target:SpawnChild("dyc_healthbar")
        target.dychealthbar.Network:SetClassifiedTarget(nearby_observer)
    else
        target.dychealthbar = SpawnPrefab("dyc_healthbar")
        target.dychealthbar.Transform:SetPosition(target:GetPosition():Get())
    end

    local health_bar = target.dychealthbar
    health_bar.dychbowner = target
    health_bar.dychbattacker = attacker

    if IsDST() then
        health_bar.dycHbIgnoreFirstDoDelta = true

        health_bar.dychp_net:set_local(0)
        health_bar.dychp_net:set(target.components.health.currenthealth)

        health_bar.dychpmax_net:set_local(0)
        health_bar.dychpmax_net:set(target.components.health.maxhealth)
    end

    health_bar:InitHB()
end

local function PatchCombatComponent(combat)
    local OriginalSetTarget = combat.SetTarget

    combat.SetTarget = function(self, target)
        if target ~= nil
            and self.inst.components.health
            and target.components.health
        then
            ShowHealthBar(target, self.inst)
            ShowHealthBar(self.inst, target)
        end

        return OriginalSetTarget(self, target)
    end

    local OriginalGetAttacked = combat.GetAttacked

    combat.GetAttacked = function(self, attacker, damage, weapon, stimuli)
        ShowHealthBar(self.inst)

        if attacker and attacker.components.health then
            ShowHealthBar(attacker)
        end

        return OriginalGetAttacked(self, attacker, damage, weapon, stimuli)
    end
end

local function PatchHealthComponent(health)
    local OriginalDoDelta = health.DoDelta

    health.DoDelta = function(self, amount, overtime, cause, ignore_invincible, afflicter, ignore_absorb)
        if amount <= -TUNING.DYC_HEALTHBAR_DDTHRESHOLD
            or (amount >= 0.9 and self.maxhealth - self.currenthealth >= 0.9)
        then
            ShowHealthBar(self.inst)
        end

        if not IsDST()
            and TUNING.DYC_HEALTHBAR_DDON
            and IsNearLocalPlayer(self.inst)
        then
            local damage_display = SpawnPrefab("dyc_damagedisplay")
            damage_display:DamageDisplay(self.inst)
        end

        local result = OriginalDoDelta(
            self,
            amount,
            overtime,
            cause,
            ignore_invincible,
            afflicter,
            ignore_absorb
        )

        if IsDST() and self.inst.dychealthbar then
            local health_bar = self.inst.dychealthbar

            local function UpdateNetworkHealth()
                health_bar.dychp_net:set_local(0)
                health_bar.dychp_net:set(self.currenthealth)

                if health_bar.dychpmax ~= self.maxhealth then
                    health_bar.dychpmax_net:set_local(0)
                    health_bar.dychpmax_net:set(self.maxhealth)
                end
            end

            if health_bar.dycHbIgnoreFirstDoDelta == true then
                health_bar.dycHbIgnoreFirstDoDelta = false
                self.inst:DoTaskInTime(0.01, UpdateNetworkHealth)
            else
                UpdateNetworkHealth()
            end
        end

        return result
    end
end

AddComponentPostInit("combat", function(_, inst)
    if not IsDST() or GLOBAL.TheWorld.ismastersim then
        if inst.components.combat then
            PatchCombatComponent(inst.components.combat)
        end
    end
end)

AddComponentPostInit("health", function(_, inst)
    if not IsDST() or GLOBAL.TheWorld.ismastersim then
        if inst.components.health then
            PatchHealthComponent(inst.components.health)
        end
    end
end)
