-- [PATCH] 新增：共享的游戏暂停管理器。
-- 原版与新增功能都需要在特定时机冻结游戏，但直接调用 TheNet:SetServerPaused
-- 会在对局进行中触发引擎断言 `Update() called on paused server!` 导致崩溃。
-- 因此统一改用 TheSim:SetTimeScale(0) 冻结时间，并支持多个暂停原因叠加，
-- 只有所有暂停原因都解除后才恢复原来的时间流速。

local _reasons = {}
local _saved_scale = nil

local M = {}

-- 添加一个暂停原因。首次调用时保存当前时间流速并冻结。
function M.Pause(reason)
    if TheSim == nil then
        return
    end
    if reason == nil then
        reason = "unknown"
    end

    if next(_reasons) == nil then
        _saved_scale = TheSim:GetTimeScale() or 1
        TheSim:SetTimeScale(0)
    end
    _reasons[reason] = true
end

-- 移除一个暂停原因。所有原因都移除后恢复之前保存的时间流速。
function M.Resume(reason)
    if TheSim == nil then
        return
    end
    if reason == nil then
        reason = "unknown"
    end

    _reasons[reason] = nil
    if next(_reasons) == nil then
        TheSim:SetTimeScale(_saved_scale or 1)
        _saved_scale = nil
    end
end

-- 当前是否处于暂停状态。
function M.IsPaused()
    return next(_reasons) ~= nil
end

return M
