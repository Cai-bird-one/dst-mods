-- First-day gameplay restrictions outside the generic player protection hooks.
-- This is a registration script and must be loaded with modimport.
local team_state = require("src/team/lobby_team_state")

local function install_staff_tornado_rule()
    AddPrefabPostInit("staff_tornado", function(inst)
        if not TheWorld.ismastersim or inst.components.spellcaster == nil then
            return
        end

        local CastSpell = inst.components.spellcaster.CastSpell
        inst.components.spellcaster.CastSpell = function(self, target, pos, doer, ...)
            -- CastSpell receives the target first. Older/custom callers may
            -- omit doer, so resolve the staff's owner only in that case.
            local caster = doer
            if caster == nil then
                local inventoryitem = inst.components.inventoryitem
                if inventoryitem ~= nil then
                    caster = inventoryitem.GetGrandOwner ~= nil
                        and inventoryitem:GetGrandOwner()
                        or inventoryitem.owner
                end
            end
            if caster ~= nil and caster:HasTag("player") and TheWorld.state.cycles < 1 then
                return
            end
            return CastSpell(self, target, pos, doer, ...)
        end
    end)
end

local function install_shadowprotector_rule()
    if not GetModConfigData("shadowprotector_change") then
        return
    end

    local function is_same_team(inst, target)
        local team_id = team_state.get_player_team(inst)
        local target_team_id = target ~= nil and team_state.get_player_team(target) or nil
        return team_state.is_playing_team(team_id)
            and team_id == target_team_id
    end

    local function can_attack(inst, target)
        if inst.components.follower ~= nil
            and inst.components.follower.leader ~= nil
            and target ~= nil
            and target:HasTag("player") then
            return TheWorld.state.cycles > 0
                or is_same_team(inst.components.follower.leader, target)
        end
        return true
    end

    AddPrefabPostInit("shadowprotector", function(inst)
        if not TheWorld.ismastersim or inst.components.combat == nil then
            return
        end

        local SetTarget = inst.components.combat.SetTarget
        inst.components.combat.SetTarget = function(self, target)
            if not can_attack(inst, target) then
                return
            end
            return SetTarget(self, target)
        end
    end)
end

install_staff_tornado_rule()
install_shadowprotector_rule()
