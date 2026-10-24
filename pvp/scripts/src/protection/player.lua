-- Shared player-effect guards.
-- Consolidates first-day protection and observer-camera immunity so each hook is installed once.
local OBSERVER_TAG = "bird_observer_camera"
local team_state = require("src/team/lobby_team_state")
local FIRST_DAY_BLOCKED_SPEED_KEYS = {
    honey_ammo_afflicted = true,
    slingshotammo_slow = true,
}

local function is_observer_camera(inst)
    if inst == nil then
        return false
    end

    local team_id, pending = team_state.get_player_team(inst)
    if pending or team_id == nil or team_state.is_playing_team(team_id) then
        return false
    end

    return team_id == team_state.TEAM_OBSERVER
end

local function is_first_day_player(inst)
    return inst ~= nil
        and inst:HasTag("player")
        and TheWorld ~= nil
        and TheWorld.state.cycles < 1
end

local function is_player_follower(attacker)
    return attacker ~= nil
        and attacker.components ~= nil
        and attacker.components.follower ~= nil
        and attacker.components.follower.leader ~= nil
        and attacker.components.follower.leader:HasTag("player")
end

local function has_hand_item(inst)
    local inventory = inst ~= nil and inst.components ~= nil and inst.components.inventory or nil
    return inventory ~= nil
        and inventory:GetEquippedItem(EQUIPSLOTS.HANDS) ~= nil
end

local function is_blocked_first_day_attack(target, attacker, weapon)
    if not is_first_day_player(target) or attacker == nil then
        return false
    end

    if attacker:HasTag("player") then
        -- Only a human player's genuinely empty-handed attack is allowed.
        -- Wereforms and hand-slot tools such as walking_stick do not always
        -- provide a weapon argument, so both must be checked explicitly.
        return weapon ~= nil
            or attacker:HasTag("wereplayer")
            or has_hand_item(attacker)
    end

    -- Tornado damage names the tornado itself as the attacker. Preserve the
    -- original player attribution even if its caster has since disconnected.
    local windstaff_caster = attacker.WINDSTAFF_CASTER
    return is_player_follower(attacker)
        or attacker.WINDSTAFF_CASTER_ISPLAYER == true
        or (windstaff_caster ~= nil and windstaff_caster:HasTag("player"))
end

local function install_health_guard()
    AddComponentPostInit("health", function(self)
        local SetInvincible = self.SetInvincible
        function self:SetInvincible(invincible, ...)
            if is_observer_camera(self.inst) then
                invincible = true
            end
            return SetInvincible(self, invincible, ...)
        end
    end)
end

local function install_control_effect_guards()
    AddComponentPostInit("freezable", function(self)
        local AddColdness = self.AddColdness
        function self:AddColdness(...)
            if is_observer_camera(self.inst) or is_first_day_player(self.inst) then
                return
            end
            return AddColdness(self, ...)
        end
    end)

    AddComponentPostInit("grogginess", function(self)
        local AddGrogginess = self.AddGrogginess
        function self:AddGrogginess(...)
            if is_observer_camera(self.inst) or is_first_day_player(self.inst) then
                return
            end
            return AddGrogginess(self, ...)
        end
    end)

    AddComponentPostInit("pinnable", function(self)
        local Stick = self.Stick
        function self:Stick(...)
            if is_observer_camera(self.inst) then
                return
            end
            return Stick(self, ...)
        end
    end)

    AddComponentPostInit("locomotor", function(self)
        local SetExternalSpeedMultiplier = self.SetExternalSpeedMultiplier
        function self:SetExternalSpeedMultiplier(source, key, multiplier, ...)
            if is_first_day_player(self.inst) and FIRST_DAY_BLOCKED_SPEED_KEYS[key] then
                return
            end
            return SetExternalSpeedMultiplier(self, source, key, multiplier, ...)
        end
    end)
end

local function install_shadow_prison_guard()
    local function guard_prefab(prefab)
        AddPrefabPostInit(prefab, function(inst)
            if not TheWorld.ismastersim or inst.SetTarget == nil then
                return
            end

            local SetTarget = inst.SetTarget
            function inst:SetTarget(target, ...)
                if is_first_day_player(target) then
                    self:Remove()
                    return
                end
                return SetTarget(self, target, ...)
            end
        end)
    end

    -- The hidden target entity applies rooted; the visible pillar entities
    -- are rejected as well so a harmless prison graphic is not left behind.
    guard_prefab("shadow_pillar_target")
    guard_prefab("shadow_pillar")
end

local function install_stategraph_guard()
    AddStategraphPostInit("wilson", function(stategraph)
        local attacked = stategraph.events.attacked
        if attacked == nil or attacked.fn == nil then
            return
        end

        local OnAttacked = attacked.fn
        stategraph.events.attacked = EventHandler("attacked", function(inst, data, ...)
            if is_observer_camera(inst)
                and not inst.sg:HasStateTag("frozen")
                and not inst.sg:HasStateTag("sleeping") then
                return
            end
            if is_blocked_first_day_attack(
                inst,
                data ~= nil and data.attacker or nil,
                data ~= nil and data.weapon or nil
            ) then
                return
            end
            return OnAttacked(inst, data, ...)
        end)
    end)
end

local function install_player_guards()
    AddPlayerPostInit(function(inst)
        if not TheWorld.ismastersim then
            return
        end

        if inst.components.combat ~= nil then
            local combat = inst.components.combat
            -- Newer DST builds route DoAttack/DoAreaAttack straight to the
            -- internal method; GetAttacked is only a public forwarding entry.
            -- Guard the shared damage path, with a fallback for older builds.
            local method = combat.GetAttacked_Internal ~= nil and "GetAttacked_Internal" or "GetAttacked"
            local GetAttacked = combat[method]
            combat[method] = function(self, attacker, damage, weapon, stimuli, ...)
                if is_observer_camera(self.inst) then
                    return false
                end

                if is_blocked_first_day_attack(self.inst, attacker, weapon) then
                    return true
                end

                return GetAttacked(self, attacker, damage, weapon, stimuli, ...)
            end
        end

        if inst.components.burnable ~= nil then
            local Ignite = inst.components.burnable.Ignite
            inst.components.burnable.Ignite = function(self, immediate, source, doer, ...)
                if TheWorld.state.cycles < 1 then
                    return
                end
                return Ignite(self, immediate, source, doer, ...)
            end
        end
    end)
end

install_health_guard()
install_control_effect_guards()
install_shadow_prison_guard()
install_stategraph_guard()
install_player_guards()
