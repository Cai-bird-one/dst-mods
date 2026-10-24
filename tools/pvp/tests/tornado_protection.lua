-- Real PVP registration files and native CastSpell / tornado / Combat methods;
-- engine entities, entity searches, inventory, health, and SG reactions are stubs.
local assertions = 0
local function eq(actual, expected, label)
    assertions = assertions + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

TheWorld = { ismastersim = true, state = { cycles = 0 } }
TheNet = { GetPVPEnabled = function() return true end }
TUNING = { TORNADO_DAMAGE = 10, PVP_DAMAGE_MOD = 0.5 }
EQUIPSLOTS = { HANDS = "hands" }
GetTime = function() return 123 end
IsRangedWeapon = function() return false end
SpDamageUtil = {
    ApplySpDefense = function(_, damage) return damage end,
    CalcTotalDamage = function(damage) return damage.planar or 0 end,
}
local prefab_hooks, player_hook, stategraph_hook = {}, nil, nil
local team_state = {
    TEAM_OBSERVER = 0,
    get_player_team = function(inst) return inst.team or 1, false end,
    is_playing_team = function(team) return team == 1 or team == 2 end,
}
local env = setmetatable({
    require = function(name)
        assert(name == "src/team/lobby_team_state")
        return team_state
    end,
    GetModConfigData = function() return false end,
    AddComponentPostInit = function() end,
    AddPrefabPostInit = function(name, fn) prefab_hooks[name] = fn end,
    AddPlayerPostInit = function(fn) player_hook = fn end,
    AddStategraphPostInit = function(name, fn)
        assert(name == "wilson")
        stategraph_hook = fn
    end,
    EventHandler = function(name, fn) return { name = name, fn = fn } end,
}, { __index = _G })
setfenv(assert(loadstring(early_game_source, "@pvp/scripts/src/gameplay/early_game.lua")), env)()
setfenv(assert(loadstring(protection_source, "@pvp/scripts/src/protection/player.lua")), env)()
local graph = { events = { attacked = { fn = function(inst) inst.staggers = inst.staggers + 1 end } } }
stategraph_hook(graph)

local function entity(player)
    local inst = { tags = { player = player }, components = {}, staggers = 0, events = {}, prefab = "test_entity" }
    function inst:HasTag(tag) return self.tags[tag] == true end
    function inst:HasAnyTag(...) for _, tag in ipairs({ ... }) do if self:HasTag(tag) then return true end end return false end
    function inst:IsValid() return true end
    function inst:GetDisplayName() return "caster" end
    function inst:GetPosition() return { x = 0, y = 0, z = 0 } end
    function inst:PushEvent(name, data)
        self.events[name] = data
        if name == "attacked" and self:HasTag("player") then graph.events.attacked.fn(self, data) end
    end
    inst.Transform = { GetWorldPosition = function() return 0, 0, 0 end, SetPosition = function() end }
    inst.sg = { HasStateTag = function() return false end, statemem = {} }
    inst.components.inventory = {
        GetEquippedItem = function() return inst.hand end,
        ApplyDamage = function(_, damage, _, _, special)
            inst.armor_calls = (inst.armor_calls or 0) + 1
            return damage, special
        end,
    }
    local health = { currenthealth = 100 }
    function health:IsDead() return self.currenthealth <= 0 end
    function health:IsInvincible() return false end
    function health:DoDelta(delta) self.currenthealth = self.currenthealth + delta return delta end
    inst.components.health = health
    local combat = setmetatable({ inst = inst }, { __index = Combat })
    combat.externaldamagetakenmultipliers = { Get = function() return 1 end }
    function combat:ShouldRecoil(_, _, damage) return false, damage end
    function combat:CalcReflectedDamage() return 0 end
    function combat:CanBeAttacked() return true end
    function combat:SuggestTarget(target) self.target = target end
    inst.components.combat = combat
    if player then player_hook(inst) end
    return inst
end

local spawns, spawned = 0, nil
SpawnPrefab = function(prefab)
    eq(prefab, "tornado", "native staff spawns tornado")
    spawns = spawns + 1
    spawned = entity(false)
    spawned.prefab = "tornado"
    spawned.components.knownlocations = { RememberLocation = function() end }
    return spawned
end

local function staff(owner, grandowner)
    local inst = entity(false)
    inst.components.inventoryitem = {
        owner = owner,
        GetGrandOwner = function() return grandowner or owner end,
    }
    inst.uses = 0
    inst.components.finiteuses = { Use = function(_, uses) inst.uses = inst.uses + uses end }
    inst.components.spellcaster = setmetatable({ inst = inst, spell = native_spawntornado }, { __index = SpellCaster })
    prefab_hooks.staff_tornado(inst)
    return inst
end

-- Same server hooks run on Master and Caves. Day-one player casts are stopped
-- for all targets; a non-player doer is not rejected merely for targeting a player.
for _, shard in ipairs({ "forest", "cave" }) do
    TheWorld.prefab = shard
    TheWorld.state.cycles = 0
    local caster, victim, tree = entity(true), entity(true), entity(false)
    for _, target in ipairs({ victim, tree }) do
        local item = staff(caster)
        local before = spawns
        item.components.spellcaster:CastSpell(target, nil, caster)
        eq(spawns, before, shard .. " first-day player cast prevented")
        eq(item.uses, 0, shard .. " blocked cast consumes no uses")
        eq(item.events.onspellcast, nil, shard .. " blocked cast dispatches no event")
    end
    for _, owner_case in ipairs({ "owner", "grandowner", "legacy-owner" }) do
        local item = owner_case == "grandowner" and staff(tree, caster) or staff(caster)
        if owner_case == "legacy-owner" then item.components.inventoryitem.GetGrandOwner = nil end
        local before = spawns
        item.components.spellcaster:CastSpell(tree)
        eq(spawns, before, shard .. " omitted doer resolves " .. owner_case)
        eq(item.uses, 0, shard .. " owner fallback preserves uses")
    end
    local ownerless = staff(nil)
    local before_ownerless = spawns
    ownerless.components.spellcaster:CastSpell(tree, nil, caster)
    eq(spawns, before_ownerless, shard .. " explicit player doer blocked without owner")
    eq(ownerless.uses, 0, shard .. " ownerless blocked cast preserves uses")
    local item = staff(tree)
    local before = spawns
    item.components.spellcaster:CastSpell(victim, nil, tree)
    eq(spawns, before + 1, shard .. " non-player caster targeting player allowed")
    eq(item.uses, 1, shard .. " allowed native cast consumes one use")
    eq(item.events.onspellcast.doer, tree, shard .. " native CastSpell forwards doer")

    TheWorld.state.cycles = 1
    item = staff(caster)
    before = spawns
    item.components.spellcaster:CastSpell(tree, nil, caster)
    eq(spawns, before + 1, shard .. " day-two player cast allowed")
    eq(spawned.WINDSTAFF_CASTER, caster, shard .. " native tornado keeps caster")
    eq(spawned.WINDSTAFF_CASTER_ISPLAYER, true, shard .. " native tornado snapshots player origin")
end

-- Existing player tornadoes cannot bypass either damage or the shared SG guard.
-- Run the actual SGtornado damage function against actual Combat entry points.
for _, shard in ipairs({ "forest", "cave" }) do
    TheWorld.prefab = shard
    for _, origin in ipairs({ "player", "removed-player", "caster-only", "wild", "mob" }) do
        for _, day in ipairs({ 0, 1 }) do
            TheWorld.state.cycles = 1
            local caster = (origin == "player" or origin == "removed-player" or origin == "caster-only") and entity(true)
                or origin == "mob" and entity(false) or nil
            local item, target = staff(caster), entity(true)
            item.components.spellcaster:CastSpell(entity(false), nil, caster)
            local tornado = spawned
            if origin == "removed-player" then tornado.WINDSTAFF_CASTER = nil end
            if origin == "caster-only" then tornado.WINDSTAFF_CASTER_ISPLAYER = nil end
            TheWorld.state.cycles = day
            TheSim = { FindEntities = function() return { target } end }
            native_tornado_damage(tornado)
            local blocked = day == 0 and (origin == "player" or origin == "removed-player" or origin == "caster-only")
            local damage = tornado.WINDSTAFF_CASTER_ISPLAYER and 5 or 10
            local label = shard .. "/" .. origin .. "/cycle=" .. day
            eq(target.components.health.currenthealth, blocked and 100 or 100 - damage, label .. " health")
            eq(target.armor_calls or 0, blocked and 0 or 1, label .. " armor entry")
            eq(target.staggers, blocked and 0 or 1, label .. " native damage SG reaction")
            local before = target.staggers
            graph.events.attacked.fn(target, { attacker = tornado, weapon = nil })
            eq(target.staggers, before + (blocked and 0 or 1), label .. " standalone attacked-event guard")
        end
    end
end

-- The day-one restriction is specific to player victims; world creatures still
-- take damage from an existing player tornado.
TheWorld.state.cycles = 1
local caster = entity(true)
staff(caster).components.spellcaster:CastSpell(entity(false), nil, caster)
local creature = entity(false)
TheWorld.state.cycles = 0
TheSim = { FindEntities = function() return { creature } end }
native_tornado_damage(spawned)
eq(creature.components.health.currenthealth, 90, "existing player tornado still damages creatures")

-- Preserve nil holes, additional arguments, and multiple return values for
-- other wrappers, including calls without any known caster or owner.
for _, day in ipairs({ 0, 1 }) do
    TheWorld.state.cycles = day
    local item, marker = entity(false), {}
    item.components.spellcaster = { CastSpell = function(self, target, pos, doer, hole, extra)
        eq(self, item.components.spellcaster, "CastSpell self preserved")
        eq(target, nil, "CastSpell nil target preserved")
        eq(pos, marker, "CastSpell position preserved")
        eq(doer, nil, "CastSpell omitted doer preserved")
        eq(hole, nil, "CastSpell nil tail preserved")
        eq(extra, marker, "CastSpell future argument preserved")
        return false, nil, marker
    end }
    prefab_hooks.staff_tornado(item)
    local a, b, c = item.components.spellcaster:CastSpell(nil, marker, nil, nil, marker)
    eq(a, false, "CastSpell first return preserved")
    eq(b, nil, "CastSpell nil return preserved")
    eq(c, marker, "CastSpell final return preserved")
end

-- Client spellcasters keep the native method, and players keep native Combat.
TheWorld.ismastersim = false
local item = staff(entity(true))
eq(item.components.spellcaster.CastSpell, SpellCaster.CastSpell, "client staff hook excluded")
local client = entity(true)
eq(client.components.combat.GetAttacked_Internal, Combat.GetAttacked_Internal, "client damage hook excluded")
return assertions
