require "TimedActions/ISBaseTimedAction"
---@class ImmersiveSolarArrays
local ISA = require "ImmersiveSolarArrays/Utilities"

ISA_ActivatePowerBank = ISBaseTimedAction:derive("ISA_ActivatePowerBank")

function ISA_ActivatePowerBank:new(character, powerbank, activate, x, y, z)
    local o = ISBaseTimedAction.new(self, character)
    o.activate = activate
    o.powerbank = powerbank
    o.isoPb = powerbank
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()

    o.x = x
    o.y = y
    o.z = z

    return o
end

function ISA_ActivatePowerBank:isValid()
    local valid = self.isoPb and self.isoPb:getObjectIndex() ~= -1 or false
    if not valid then
        ISA.debugLog("Activation action invalid x=%s y=%s z=%s reason=object-removed",
            tostring(self.x), tostring(self.y), tostring(self.z))
    end
    return valid
end

function ISA_ActivatePowerBank:start()
    ISA.debugLog("Activation action started x=%s y=%s z=%s enabled=%s side=%s",
        tostring(self.x), tostring(self.y), tostring(self.z), tostring(self.activate), isClient() and "client" or "server")
end

function ISA_ActivatePowerBank:stop()
    ISA.debugLog("Activation action stopped x=%s y=%s z=%s", tostring(self.x), tostring(self.y), tostring(self.z))
    ISBaseTimedAction.stop(self)
end

function ISA_ActivatePowerBank:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end
    return 40 - 3 * self.character:getPerkLevel(Perks.Electricity)
end

function ISA_ActivatePowerBank:complete()
    if isClient() then
        ISA.PBSystem_Client:sendCommand(self.character, "activatePowerbank", {
            pb = { x = self.x, y = self.y, z = self.z },
            activate = self.activate
        })
        return true
    end

    local system = ISA.PBSystem_Server
    local pb = system and system:getLuaObjectAt(self.x, self.y, self.z)
    ISA.debugLog("Activation action completed on server x=%s y=%s z=%s bankFound=%s",
        tostring(self.x), tostring(self.y), tostring(self.z), tostring(pb ~= nil))
    return system and system:setBankEnabled(self.character, pb, self.activate) or false
end

ISA.ActivatePowerbank = ISA_ActivatePowerBank

return ISA_ActivatePowerBank
