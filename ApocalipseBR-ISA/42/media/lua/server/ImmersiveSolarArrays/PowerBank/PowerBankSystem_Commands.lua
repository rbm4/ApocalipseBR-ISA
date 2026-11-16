if isClient() then return end

---@class PowerbankSystem_Server
local PBSystem = require "ImmersiveSolarArrays/PowerBank/PowerBankSystem_Server"

local Commands = {}

local function noise(message) return PBSystem.instance:noise(message) end

---@param args table
---@return PowerBankObject_Server
local function getPowerBank(args)
    return PBSystem.instance:getLuaObjectAt(args.x, args.y, args.z)
end

local function settled(bank, command, player, args)
    local ISA = require "ImmersiveSolarArrays/Utilities"
    if not ISA.NativeSimulation or ISA.NativeSimulation.ensureCurrent(bank) then return true end
    ISA.NativeSimulation.queueCommand(bank,command,player,args)
    return false
end

function Commands.disconnectPanel(player,args)
    if not args or not args.pb or not args.panel then return end
    local pb = getPowerBank(args.pb)
    if pb == nil then return end
    if not settled(pb,"disconnectPanel",player,args) then return false end
    for i,panel in ipairs(pb.panels) do
        if panel.x == args.panel.x and panel.y == args.panel.y and panel.z == args.panel.z then
            table.remove(pb.panels,i)
            pb.npanels = pb.npanels - 1
            break
        end
    end
    pb:saveData(true)
end

function Commands.connectPanel(player,args)
    if not args or not args.pb or not args.panel then return end
    local pb = getPowerBank(args.pb)
    if pb == nil then return end
    if not settled(pb,"connectPanel",player,args) then return false end

    local x,y,z = args.panel.x,args.panel.y,args.panel.z
    local square = getSquare(x,y,z)
    if square == nil then return end

    local panel, status = pb:getPanelStatusOnSquare(square)
    if panel == nil or status ~= "not connected" then return end

    table.insert(pb.panels,args.panel)
    pb.npanels = pb.npanels + 1
    pb:saveData(true)
end

function Commands.moveBattery(player,args)
    local pb = getPowerBank(args[1])
    if pb == nil then return end
    if not settled(pb,"moveBattery",player,args) then return false end
    noise("Transfering Battery")
    if args[2] == "take" then
        pb.batteries = pb.batteries - 1
        if pb.batteries > 0 then
            pb.charge = pb.charge - args[3]
            pb.maxcapacity = pb.maxcapacity - args[4]
        else
            pb.charge = 0
            pb.maxcapacity = 0
        end
    elseif args[2] == "put" then
        pb.batteries = pb.batteries + 1
        pb.charge = pb.charge + args[3]
        pb.maxcapacity = pb.maxcapacity + args[4]
    end
    pb:updateGenerator()
    pb:updateSprite()
    pb:saveData(true)
end

function Commands.plugGenerator(player,args)
    if type(args)~="table" or type(args.gen)~="table" or type(args.pbList)~="table" or type(args.plug)~="boolean" then return false end
    if #args.pbList > 64 then return false end
    local ISA=require "ImmersiveSolarArrays/Utilities"
    local function coordinates(value)
        return type(value)=="table" and type(value.x)=="number" and value.x%1==0
            and type(value.y)=="number" and value.y%1==0 and type(value.z)=="number" and value.z%1==0
    end
    if not coordinates(args.gen) then return false end
    local square = getSquare(args.gen.x,args.gen.y,args.gen.z)
    local generator = square and square:getGenerator()
    if args.plug and (not generator or not generator:isConnected()) then return false end
    local accepted=false
    for _,i in ipairs(args.pbList) do
        local pb = coordinates(i) and getPowerBank(i)
        local one={gen=args.gen,plug=args.plug,pbList={i}}
        local nearby=pb and (ISA.WorldUtil.isWithinPowerBankRange(player,pb:getSquare())
            or (square and ISA.WorldUtil.isWithinPowerBankRange(player,square)))
        local link=pb and pb.conGenerator
        local matching=link and link.x==args.gen.x and link.y==args.gen.y and link.z==args.gen.z
        if pb and nearby and (args.plug or matching) then
            if args.plug then
                local area=ISA.WorldUtil.getValidBackupArea(SandboxVars.ISA.BackupGeneratorRange)
                if IsoUtils.DistanceToSquared(pb.x,pb.y,args.gen.x,args.gen.y)>area.distance or math.abs(pb.z-args.gen.z)>area.levels then return false end
            end
            if settled(pb,"plugGenerator",player,one) then
                local changed
                if args.plug then
                    noise("adding backup")
                    changed=pb:connectBackupGenerator(generator)
                else
                    noise("removing backup")
                    changed=pb:disconnectBackupGenerator()
                end
                accepted=changed~=false or accepted
            else
                accepted=true
            end
        end
    end
    return accepted
end

function Commands.activateGenerator(player,args)
    local ISA=require "ImmersiveSolarArrays/Utilities"
    if ISA.NativeSimulation then return false end
    if not args or not args.pb then return end
    local pb = getPowerBank(args.pb)
    if pb and pb.conGenerator then
        pb.conGenerator.ison = args.activate
        pb:saveData(true)
    end
end

function Commands.activatePowerbank(player,args)
    if type(args) ~= "table" or type(args.pb) ~= "table" or type(args.activate) ~= "boolean" then return end
    local pb = getPowerBank(args.pb)
    if pb then
        PBSystem.instance:setBankEnabled(player, pb, args.activate)
    end
end

function Commands.refreshPowerbank(player, args)
    if type(args) ~= "table" or type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number" then return false end
    if args.x % 1 ~= 0 or args.y % 1 ~= 0 or args.z % 1 ~= 0 then return false end
    local bank = getPowerBank(args)
    local generator = bank and bank:getIsoObject()
    local ISA = require "ImmersiveSolarArrays/Utilities"
    if not generator or not ISA.WorldUtil.isWithinPowerBankRange(player, generator:getSquare()) then return false end
    local now = getTimestampMs()
    if bank.nextDeviceRefreshMs and now < bank.nextDeviceRefreshMs then return false end
    bank.nextDeviceRefreshMs = now + 1000

    if ISA.NativeSimulation then
        -- The scheduler owns the server scan and final broadcast, including UI requests.
        bank._ISA_forceDevices=true
        generator:requestSimulationUpdate()
        generator:update()
        return true
    end

    generator:setSurroundingElectricity()
    bank:updateDrain()
    if ISA.nativePowerBanks then
        generator:requestSimulationUpdate()
        generator:update()
    end
    bank:saveData(true)
    ISA.debugLog("Devices refreshed on server x=%s y=%s z=%s drain=%.3f devices=%s",
        tostring(bank.x), tostring(bank.y), tostring(bank.z), bank.drain, tostring(generator:getItemsPowered()))
    return true
end

function Commands.countBatteries(player,args)
    local pb = getPowerBank(args)
    local isopb = pb and pb:getIsoObject()
    if isopb then
        pb:calculateBatteryStats(isopb:getContainer())
        pb:updateSprite()
        pb:saveData(true)
    end
end

function Commands.troubleshoot(player, args)
    local pb = getPowerBank(args)
    if not pb then return end

    local isoPB = pb:getIsoObject()
    if not isoPB then return end

    -- remove invalid generators
    local objects = pb:getIsoObject():getSquare():getSpecialObjects()
    for i = objects:size() - 1, 0 , -1 do
        local object = objects:get(i)
        if instanceof(object, "IsoGenerator") and (object:getSprite() == nil or object:getModData().generatorFullType == "ISA.PowerBank_test") then
            object:remove()
        end
    end

    -- remove old attached sprites
    local attached = isoPB:getAttachedAnimSprite()
    if attached then
        attached:clear()
    end

    pb:calculateBatteryStats(isoPB:getContainer())
    pb:updateSprite()
    pb:saveData(true)
end

PBSystem.Commands = Commands
