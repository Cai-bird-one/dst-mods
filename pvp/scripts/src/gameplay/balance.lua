-- Global balance constants and configurable loot behavior.
-- This is a registration script and must be loaded with modimport.

TUNING.PANFLUTE_USES = 3

if GetModConfigData("extra_loot") == true then
    AddComponentPostInit("lootdropper", function(self)
        local DropLoot = self.DropLoot

        function self:DropLoot(...)
            -- Preserve original behavior: epic entities call DropLoot twice here,
            -- then once more below (three calls in total).
            if self.inst:HasTag("epic") then
                DropLoot(self, ...)
                DropLoot(self, ...)
            end
            DropLoot(self, ...)
        end
    end)
end
