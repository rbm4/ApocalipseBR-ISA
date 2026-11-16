---@class ImmersiveSolarArrays
local ISA = require "ImmersiveSolarArrays/Utilities"

ISA.Patches = {}


ISA.Patches["ISActivateGenerator.complete"] = function ()
    local originalValid = ISActivateGenerator.isValid
    ISActivateGenerator.isValid = function(self)
        if ISA.WorldUtil.isManagedBackup(self.generator) then return false end
        return originalValid(self)
    end
    local original = ISActivateGenerator.complete
    ISActivateGenerator.complete = function (self)
        if ISA.WorldUtil.isManagedBackup(self.generator) then return false end
        local result = original(self)

        --check action was successful
        if result and self.activate == self.generator:isActivated() and ISA.PBSystem_Server then
            ISA.PBSystem_Server:onActivateGenerator(self.character, self.generator, self.activate)
        end

        return result
    end
end

ISA.Patches["ISPlugGenerator.complete"] = function()
    local originalValid, originalComplete = ISPlugGenerator.isValid, ISPlugGenerator.complete
    ISPlugGenerator.isValid = function(self)
        if not self.plug and ISA.WorldUtil.isManagedBackup(self.generator) then return false end
        return originalValid(self)
    end
    ISPlugGenerator.complete = function(self)
        if not self.plug and ISA.WorldUtil.isManagedBackup(self.generator) then return false end
        return originalComplete(self)
    end
end


ISA.queueFunction("OnTick", function (tick)
    for _, patch in pairs(ISA.Patches) do
        patch()
    end
    ISA.Patches = nil
end)
