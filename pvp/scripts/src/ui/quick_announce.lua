-- Loads the quick announce module when the original environment checks pass.

if not GetModConfigData("quick_announce") then
    return
end

local is_supported_host = TheNet:GetIsClient()
    or (
        TheNet:GetServerIsClientHosted()
        and not TheNet:GetIsClient()
        and not TheNet:IsDedicated()
    )

if not is_supported_host then
    return
end

modimport("scripts/src/ui/wx78_quick_announce_guard.lua")
modimport("scripts/qa_main.lua")
