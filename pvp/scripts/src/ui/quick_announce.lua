-- Loads the quick announce module when the original environment checks pass.

local debug_log = require("src/core/debug")

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

local base_add_class_post_construct = AddClassPostConstruct
if type(base_add_class_post_construct) == "function" then
    AddClassPostConstruct = function(classname, postfn)
        if classname == "widgets/upgrademodulesdisplay" and type(postfn) == "function" then
            return base_add_class_post_construct(classname, function(...)
                local wx78_guard = rawget(_G, "BIRD_WX78_QUICK_ANNOUNCE_GUARD")
                if wx78_guard ~= nil and type(wx78_guard.prepare_display) == "function" then
                    wx78_guard.prepare_display(...)
                end

                local ok, result = pcall(postfn, ...)
                if wx78_guard ~= nil and type(wx78_guard.prepare_display) == "function" then
                    wx78_guard.prepare_display(...)
                end
                if wx78_guard ~= nil and type(wx78_guard.wrap_on_module_added) == "function" then
                    wx78_guard.wrap_on_module_added(...)
                end

                if ok then
                    return result
                end
                debug_log.error("wx78-qa-guard", "post construct", tostring(result))
                return false
            end)
        end

        return base_add_class_post_construct(classname, postfn)
    end
end

modimport("scripts/src/ui/wx78_quick_announce_guard.lua")
modimport("scripts/qa_main.lua")

if type(base_add_class_post_construct) == "function" then
    AddClassPostConstruct = base_add_class_post_construct
end
