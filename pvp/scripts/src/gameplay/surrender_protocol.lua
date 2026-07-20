local M = {}

M.RPC_NAMESPACE = "bird_pvp_surrender"
M.MOD_RPC_START = "start"
M.MOD_RPC_VOTE = "vote"
M.SHARD_RPC_START = "start"
M.SHARD_RPC_VOTE = "vote"
M.SHARD_RPC_SYNC = "sync"

M.VOTE_YES = 1
M.VOTE_NO = 2
M.VOTE_DURATION = 30

M.NET_DIRTY_EVENT = "bird_surrender_vote_dirty"
M.NET_ACTIVE = "bird_surrender_vote.active"
M.NET_TEAM = "bird_surrender_vote.team"
M.NET_REMAINING = "bird_surrender_vote.remaining"
M.NET_YES_UNITS = "bird_surrender_vote.yes_units"
M.NET_NO_UNITS = "bird_surrender_vote.no_units"
M.NET_STARTER = "bird_surrender_vote.starter"
M.NET_SERIAL = "bird_surrender_vote.serial"

function M.format_units(units)
    units = math.floor(math.max(0, tonumber(units) or 0))
    if units % 2 == 0 then
        return tostring(units / 2)
    end
    return string.format("%.1f", units / 2)
end

function M.has_passed(yes_units, no_units)
    yes_units = math.max(0, tonumber(yes_units) or 0)
    no_units = math.max(0, tonumber(no_units) or 0)
    return yes_units > no_units * 2
end

return M
