--[[
    "isa_powerbank" server luaObject
--]]

if isClient() then return end

require "Map/SGlobalObject"
local ISA = require "ImmersiveSolarArrays/Utilities"
local Grid = require "ImmersiveSolarArrays/GridPower"
local solarscan = require "ImmersiveSolarArrays/PowerBank/SolarScan"
local sandbox = SandboxVars.ISA

---@class PowerBankObject_Server : SGlobalObject
---@field luaSystem PowerbankSystem_Server
local PowerBank = SGlobalObject:derive("ISA_PowerBank_Server")

function PowerBank:new(luaSystem, globalObject)
    local bank = SGlobalObject.new(self, luaSystem, globalObject)
    ISA.debugLog("Registered bank x=%s y=%s z=%s mode=%s savedHour=%s",
        tostring(bank.x), tostring(bank.y), tostring(bank.z),
        ISA.nativePowerBanks and "native" or "legacy", tostring(bank.ISA_simulationHour))
    return bank
end

function PowerBank:initNew()
    ISA.debugLog("Initializing bank x=%s y=%s z=%s", tostring(self.x), tostring(self.y), tostring(self.z))

    self.on = false
    self.batteries = 0
    self.charge = 0
    self.maxcapacity = 0
    self.panels = {}
    self.npanels = 0
    self.drain = 0
    self.lastHour = 0
    self.conGenerator = false ---FIXME should be nil, nil didn't save / transmit data?
    self.ISA_simulationHour = getGameTime():getWorldAgeHours()
end

---called from loadIsoObject function when making new globalObject & luaObject. This is called for IsoObjects that did not have a Lua object when loaded.
---triggered by: Events.OnObjectAdded, MapObjects.OnLoadWithSprite
function PowerBank:stateFromIsoObject(isoObject)
    isoObject:createContainersFromSpriteProperties()
    isoObject:getContainer():setExplored(true)
    isoObject:setCondition(100)
    isoObject:setFuel(100)
    isoObject:setConnected(true)

    self:initNew()
    self:calculateBatteryStats(isoObject:getContainer())
    -- Removed self:autoConnectBackup() for manual backup generator connection feature
    -- self:createGenerator() --if generator...
    self:loadGenerator()
    self:updateDrain()
    self:updateSprite()
    self:saveData(true)
end

---called from loadIsoObject function when luaObject exists, triggered by: Events.OnObjectAdded, MapObjects.OnLoadWithSprite
function PowerBank:stateToIsoObject(isoObject)
    self:toModData(isoObject:getModData())
    isoObject:transmitModData()
    self:loadGenerator()
    self:updateSprite()
end

function PowerBank:fromModData(modData)
    for i, key in ipairs(self.luaSystem.savedObjectModData) do
        self[key] = modData[key]
    end
end

function PowerBank:toModData(modData)
    for i, key in ipairs(self.luaSystem.savedObjectModData) do
        modData[key] = self[key]
    end
end

function PowerBank:saveData(transmit)
    if ISA.NativeSimulation and not self._ISA_processing and self.ISA_simulationHour == getGameTime():getWorldAgeHours() then
        self.ISA_energyConfig={on=self.on,drain=self.drain,npanels=self.npanels,maxcapacity=self.maxcapacity,
            indoors=self.ISA_energyConfig and self.ISA_energyConfig.indoors,
            gridEligible=self.ISA_energyConfig and self.ISA_energyConfig.gridEligible}
    end
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    self:toModData(isoObject:getModData())
    if transmit then
        isoObject:transmitModData()
    end
end

function PowerBank:shouldDrain(isoPb)
    if self.switchchanged then
        self.switchchanged = nil
    elseif not self.on then
        return false
    end
    if self.conGenerator and self.conGenerator.ison then return false end

    if isoPb then
        if Grid.current(isoPb:getSquare()) then return false end
    elseif self.ISA_energyConfig and self.ISA_energyConfig.gridEligible==true and Grid.exists() then return false end
    return true
end

PowerBank.fuelToSolarRate = 800
function PowerBank:getDrainVanilla(square)
    local gen = square:getGenerator()
    if ISA.nativePowerBanks then
        return gen:getTotalPowerUsing() * self.fuelToSolarRate
    end
    if gen:isActivated() then
        gen:setSurroundingElectricity()
        return gen:getTotalPowerUsing() * self.fuelToSolarRate
    else
        return PowerBank.getTotalWhenoff(gen) * self.fuelToSolarRate
    end
end

function PowerBank.getTotalWhenoff(generator)
    generator:setActivated(true)
    local tpu = generator:getTotalPowerUsing()
    generator:setActivated(false)
    if generator:getSquare():getBuilding() ~= nil then generator:getSquare():getBuilding():setToxic(false) end
    return tpu
end

function PowerBank:updateDrain()
    local square = self:getSquare()
    if not square then return end
    if sandbox.DrainCalc == 1 then
        self.drain = solarscan(square, false, true, false, 0)
    else
        self.drain = PowerBank:getDrainVanilla(square)
    end
end

---@param container ItemContainer
---@param modCharge number
function PowerBank:updateBatteries(container, modCharge)
    local items = container:getItems()
    for i = items:size() - 1, 0, -1  do
        local item = items:get(i)
        -- bugfix
        if container:isItemAllowed(item) then
            item:setCurrentUsesFloat(modCharge)
        else
            container:Remove(item)
            self:getSquare():AddWorldInventoryItem(item, 0.5, 0.5, 0)
            print("ISA: Removed invalid item from Battery Bank. ->", item:getFullType())
        end
    end
    -- container:setDirty(true)
    container:setDrawDirty(true)
end

-- SPowerbank.batteryDegrade = {
--     ["WiredCarBattery"] = 7, --ModData
--     ["DIYBattery"] = 0.125,
--     ["DeepCycleBattery"] = 0.033,
--     ["SuperBattery"] = 0.033,
-- }

--condition is an int
function PowerBank:degradeBatteries(container)
    if sandbox.batteryDegradeChance == 0 then return end

    local ZombRand, math = ZombRand, math
    local mod = sandbox.batteryDegradeChance * ZombRand(8, 13) / 1000

    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do repeat
        local item = items:get(i)
        local degradeVal = item:getModData()["ISA_BatteryDegrade"] or 0 --or self.batteryDegrade[item:getType()]
        if degradeVal <= 0 then break end
        -- average of 1M rolls / 10: 5.5 / 3: 2 / 1.6: 1.37364 / 0.9: 0.90082 / 0.033: 0.03280
        degradeVal = degradeVal * mod
        degradeVal = degradeVal > 1 and 1 + math.floor(ZombRand(degradeVal * 100) / 100) or math.floor(ZombRand(100 / degradeVal) / 100 ) == 0 and 1 or 0
        if degradeVal <= 0 then break end
        item:setCondition(item:getCondition() - degradeVal)
    until true
    end
end

function PowerBank:calculateBatteryStats(container)
    local batteries = 0
    local capacity = 0
    local charge = 0

    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local maxCapacity = item:getModData().ISA_maxCapacity
        if maxCapacity then
            local condition = item:getCondition()
            if condition > 0 then
                batteries = batteries + 1
                local cap = maxCapacity * (1 - math.pow((1 - (condition/100)),6))
                capacity = capacity + cap
                charge = charge + cap * item:getCurrentUsesFloat()
            end
        else
            print("ISA: Warning invalid item in Battery Bank. -> ", item:getFullType())
        end
    end

    self.batteries = batteries
    self.maxcapacity = capacity
    self.charge = charge
end

function PowerBank:getPanelStatus(panel)
    local x,y,z = panel:getX(), panel:getY(), panel:getZ()
    if IsoUtils.DistanceToSquared(x, y, self.x, self.y) <= 400.0 and math.abs(z - self.z) <= 3 then
        for _, panelXYZ in ipairs(self.panels) do
            if x == panelXYZ.x and y == panelXYZ.y and z == panelXYZ.z then return "connected" end
        end
        return "not connected"
    else
        return "far"
    end
end

---checks the square for a panel object and returns the object and status
function PowerBank:getPanelStatusOnSquare(square)
    local panel = ISA.WorldUtil.findTypeOnSquare(square, "Panel")
    if panel ~= nil then
        return panel, square:isOutside() and self:getPanelStatus(panel) or "indoors"
    end
    return nil, ""
end

---bugfix, verify panels
function PowerBank:checkPanels()
    local getSquare = getSquare

    local dup = {}
    for i = #self.panels, 1, -1 do
        local panel = self.panels[i]
        local square = getSquare(panel.x, panel.y, panel.z)
        if square ~= nil then --TODO check if chunk loaded
            local panelObj, status = self:getPanelStatusOnSquare(square)
            if not panelObj or status ~= "connected" or dup[square] then
                table.remove(self.panels, i)
                if panelObj ~= nil then
                    panelObj:getModData().pbLinked = nil
                    panelObj:transmitModData()
                end
            end
            dup[square] = true
        end
    end
    self.npanels = #self.panels
end

---@param modCharge number
---@return string?
function PowerBank:getSpriteForOverlay(modCharge)
    if not self.batteries or self.batteries <= 0 then return nil end
    if modCharge == nil then modCharge = self.maxcapacity > 0 and self.charge / self.maxcapacity or 0 end
    
    local tier = math.min(math.max(math.floor((self.batteries - 1) / 4), 0), 4)
    local bracket
    if modCharge < 0.10 then bracket = 0
    elseif modCharge < 0.35 then bracket = 1
    elseif modCharge < 0.65 then bracket = 2
    elseif modCharge < 0.95 then bracket = 3
    else bracket = 4 end
    
    local spriteId = bracket == 0 and (1 + tier) or (16 + tier * 4 + bracket - 1)
    return "solarmod_tileset_01_" .. spriteId
end

function PowerBank:updateSprite(modCharge)
    local newSprite = self:getSpriteForOverlay(modCharge)
    local isoObject = self:getIsoObject()
    local attached = isoObject:getAttachedAnimSprite()

    if attached ~= nil then
        for i = 0, attached:size() - 1 do
            local attachedSprite = attached:get(i)
            local attachedName = attachedSprite:getName()
            if attachedName == newSprite then return end
            if attachedName and string.find(attachedName, "^solarmod_tileset_01_") then
                isoObject:RemoveAttachedAnim(i)
                break
            end
        end
    end
    if newSprite ~= nil then
        isoObject:addAttachedAnimSpriteByName(newSprite)
    end
end

---FIXME update
function PowerBank:createGenerator()
    self:noise("Creating Generator")
    -- local square = self:getSquare()
    -- local generator = IsoGenerator.new(instanceItem("ISA.PowerBank_test"), square:getCell(), square) --FIXME test invisible
    -- generator:setSprite(nil)
    -- generator:transmitCompleteItemToClients()
    -- generator:setCondition(100)
    -- generator:setFuel(100)
    -- generator:setConnected(true)
    -- generator:getCell():addToProcessIsoObjectRemove(generator)
end

---FIXME update
function PowerBank:removeGenerator()
    local square = self:getSquare()
    local gen = square:getGenerator()
    if gen then
        gen:setActivated(false)
        gen:remove() --index error
        --square:transmitRemoveItemFromSquare(gen) --index error
    end
end

---FIXME should not include next charge or duplicate current dCharge?
function PowerBank:updateGenerator(dCharge)
    if ISA.nativePowerBanks then
        local generator = self:getIsoObject()
        if generator then
            local fraction = self.maxcapacity > 0 and self.charge / self.maxcapacity or 0
            generator:applyPowerState(self.on and self.charge > 0, fraction)
            generator:requestSimulationUpdate()
        end
        return
    end
    if dCharge == nil then
        dCharge = self.luaSystem:getModifiedSolarOutput(self.npanels) - self.drain
        if sandbox.ChargeFreq == 1 then
            dCharge = dCharge / 6
        end
    end
    local activate = self.on and self.charge + dCharge > 0
    local gen = self:getIsoObject()
    if not gen then
        local square = self:getSquare()
        if square then
            gen = square:getGenerator()
        end
    end
    if gen then
        if not gen:isConnected() then
            gen:setConnected(true)
        end
        gen:setActivated(activate)
        gen:setFuel(100)
        gen:setCondition(100)
        gen:setSurroundingElectricity()
        if gen.updateSurroundingNow then
            gen:updateSurroundingNow()
        end
        if gen.sync then
            gen:sync()
        end
        gen:getCell():addToProcessIsoObjectRemove(gen)
    end
    local sq = self:getSquare()
    if sq and sq:getBuilding() ~= nil then sq:getBuilding():setToxic(false) end
end

--if freezer timers, Powerbank generator condition / fuel are wrong check here
function PowerBank:loadGenerator()
    if ISA.nativePowerBanks then
        local generator = self:getIsoObject()
        if generator then
            ISA.debugLog("Native bank bound x=%s y=%s z=%s subclass=%s; simulation update requested",
                tostring(self.x), tostring(self.y), tostring(self.z), tostring(instanceof(generator, "IsoPowerBank")))
            generator:requestSimulationUpdate()
        end
        return
    end
    ---new load
    local generator = self:getIsoObject()
    if not generator then
        local sq = self:getSquare()
        if sq then
            generator = sq:getGenerator()
        end
    end
    if generator then
        if not generator:isConnected() then
            generator:setConnected(true)
        end
        generator:setSurroundingElectricity()
        if generator.updateSurroundingNow then
            generator:updateSurroundingNow()
        end
        if generator.sync then
            generator:sync()
        end
        generator:getCell():addToProcessIsoObjectRemove(generator)
    end
    self:updateGenerator()
    self:updateConGenerator()
    local square = self:getSquare()
    if square and square:getBuilding() ~= nil then
        square:getBuilding():setToxic(false)
    end
end

---FIXME update
function PowerBank:fixIndex()
    if self.fixIndex_done then return end
    self.fixIndex_done = true

    local square = self:getSquare()
    local bank,hasGen

    -- Check both special objects and regular objects for B42 compatibility
    local function checkObjects(objects)
        local i = 0
        while i < objects:size() do
            local obj = objects:get(i)
            if not bank and (ISA.WorldUtil.getSpriteName(obj) == "solarmod_tileset_01_0" or ISA.WorldUtil.getType(obj) == "PowerBank") then
                bank = true
            elseif instanceof(obj,"IsoGenerator") then
                if bank and not hasGen then
                    hasGen = true
                else
                    obj:remove()
                    i=i-1
                end
            end
            i = i +1
        end
    end

    checkObjects(square:getSpecialObjects())
    if not bank then
        checkObjects(square:getObjects())
    end

    if self.conGenerator then
        local conGenerator,conSquare = self:getConGenerator()
        if conSquare and not self.luaSystem:getValidBackupOnSquare(conSquare) then
            -- Removed self:autoConnectBackup() for manual backup generator connection feature
            self.conGenerator = false
        end
    end
    if not hasGen then self:createGenerator() end
end

function PowerBank:connectBackupGenerator(generator)
    if self.conGenerator and self.conGenerator.x==generator:getX() and self.conGenerator.y==generator:getY() and self.conGenerator.z==generator:getZ() then return true end
    if ISA.nativePowerBanks and not PowerBankBackup.claim(generator,{x=self.x,y=self.y,z=self.z}) then
        ISA.debugLog("Backup connection rejected: generator already owned or managed")
        return false
    end
    if self.conGenerator then self:disconnectBackupGenerator() end
    self.conGenerator = {}
    self.conGenerator.x = generator:getX()
    self.conGenerator.y = generator:getY()
    self.conGenerator.z = generator:getZ()
    self.conGenerator.ison = generator:isActivated()
    self.ISA_backup = nil
    if ISA.NativeSimulation then ISA.NativeSimulation.bindBackup(self,generator) end
    self.lastHour = 0
    self:saveData(true)
    ISA.debugLog("Backup attached under automatic bank control x=%s y=%s z=%s source=%s,%s,%s",
        tostring(self.x),tostring(self.y),tostring(self.z),tostring(self.conGenerator.x),tostring(self.conGenerator.y),tostring(self.conGenerator.z))
    return true
end

function PowerBank:disconnectBackupGenerator(generator)
    local link=self.conGenerator
    if not link then return false end
    if generator and (generator:getX()~=link.x or generator:getY()~=link.y or generator:getZ()~=link.z) then return false end
    generator = generator or self:getConGenerator()
    if ISA.nativePowerBanks then
        if generator then
            if PowerBankBackup.isControlled(generator) then
                local owner=generator:getISABackupOwner()
                if owner.x~=self.x or owner.y~=self.y or owner.z~=self.z then
                    self.conGenerator=false
                    self.ISA_backup=nil
                    self.ISA_backupStatus=nil
                    self:saveData(true)
                    return true
                end
            end
            local state=self.ISA_backup
            if state and PowerBankBackup.isControlled(generator) then
                -- Never refund fuel already consumed by a persisted partial batch.
                generator:applyISABackupState(math.min(generator:getFuel(),state.fuel),
                    math.min(generator:getCondition(),state.condition),false)
            end
            PowerBankBackup.release(generator)
        end
        self.ISA_backup = nil
    elseif generator then
        generator:setActivated(false)
    end
    self.conGenerator = false
    self.ISA_backupStatus=nil
    self:saveData(true)
    ISA.debugLog("Backup disconnected x=%s y=%s z=%s sourceLoaded=%s; loaded source stopped before release",
        tostring(self.x),tostring(self.y),tostring(self.z),tostring(generator~=nil))
    return true
end

function PowerBank:autoConnectBackup()
    local area = ISA.WorldUtil.getValidBackupArea(3)

    self.conGenerator = false
    for ix = self.x - area.radius, self.x + area.radius do
        for iy = self.y - area.radius, self.y + area.radius do
            for iz = self.z - area.levels, self.z + area.levels do
                if ix >= 0 and iy >= 0 and iz >= 0 then
                    local isquare = IsoUtils.DistanceToSquared(self.x,self.y,self.z,ix,iy,iz) <= area.distance and getSquare(ix, iy, iz)
                    local generator = isquare and self.luaSystem:getValidBackupOnSquare(isquare)
                    if generator then
                        self:connectBackupGenerator(generator)
                        return
                    end
                end
            end
        end
    end
end

function PowerBank:getConGenerator()
    if self.conGenerator then
        local square = getSquare(self.conGenerator.x,self.conGenerator.y,self.conGenerator.z)
        if square then
            local generator = square:getGenerator()
            if not generator then self.conGenerator = false end
            return generator, square
        end
    end
    return nil
end

function PowerBank:updateConGenerator()
    if ISA.nativePowerBanks then return end
    local currentHour = math.floor(getGameTime():getWorldAgeHours())
    if self.lastHour == currentHour then return end
    local conGenerator,square = self:getConGenerator()
    if conGenerator then

        conGenerator:update()

        if self.on and ISA.WorldUtil.findOnSquare(square, "solarmod_tileset_01_15") then
            local minfailsafe = self.drain
            if conGenerator:isActivated() then
                if self.charge > minfailsafe then conGenerator:setActivated(false)end
            else
                if self.charge < minfailsafe and conGenerator:getFuel() > 0 and conGenerator:getCondition() > 20 then conGenerator:setActivated(true) end
            end
        end
        self.lastHour = currentHour
        -- if isActive ~= setActive then
        self.conGenerator.ison = conGenerator:isActivated()
    end
end

return PowerBank
