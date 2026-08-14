-- Central policy for the admin-only privileges that remain after OB migration.
local M = {}

function M.is_lobby_admin(client)
    return client ~= nil and client.admin == true
end

function M.is_local_server_admin()
    return TheNet ~= nil
        and TheNet.GetIsServerAdmin ~= nil
        and TheNet:GetIsServerAdmin()
end

function M.is_player_admin(player)
    if player == nil or player.userid == nil or TheNet == nil or TheNet.GetClientTableForUser == nil then
        return false
    end

    return M.is_lobby_admin(TheNet:GetClientTableForUser(player.userid))
end

function M.is_excluded_from_auto_team(client)
    return M.is_lobby_admin(client)
end

return M
