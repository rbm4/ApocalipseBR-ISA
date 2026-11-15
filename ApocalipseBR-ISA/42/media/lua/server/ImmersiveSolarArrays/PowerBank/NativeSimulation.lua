if isClient() then return end

local ISA = require "ImmersiveSolarArrays/Utilities"
local Native = {}
local HISTORY_KEY = "ApocBRISA_Production"
local MAX_SEGMENTS = 128
local started = false

local function history()
    local data = ModData.getOrCreate(HISTORY_KEY)
    data.samples = data.samples or {}
    return data.samples
end

function Native.recordProduction()
    local system = ISA.PBSystem_Server
    if not system then return end
    local samples = history()
    local now = getGameTime():getWorldAgeHours()
    local previous = samples[#samples]
    if previous and previous.hour >= now then return end
    local output = system:getModifiedSolarOutput(1)
    samples[#samples + 1] = { hour = now, output = output }
    ISA.debugLog("Production recorded hour=%.3f outputPerPanel=%.3f samples=%d", now, output, #samples)
end

-- Binary search avoids visiting the entire shared history for a current bank.
local function sampleAt(samples, hour)
    local low, high = 1, #samples
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if samples[middle].hour <= hour then
            low = middle + 1
        else
            high = middle - 1
        end
    end
    return math.max(1, high)
end

function Native.advance(bank, now, drain)
    local samples = history()
    if #samples == 0 then Native.recordProduction() end
    if #samples == 0 then return nil end
    local start = bank.ISA_simulationHour or now
    if start > now then start = now end
    local initialHour = start
    local index = sampleAt(samples, start)
    local processed = 0
    while start < now and processed < MAX_SEGMENTS do
        local sample = samples[index]
        local nextSample = samples[index + 1]
        local finish = nextSample and math.min(nextSample.hour, now) or now
        local rate = sample.output * bank.npanels - drain
        bank.charge = math.max(0, math.min(bank.maxcapacity, bank.charge + rate * (finish - start)))
        start = finish
        index = index + 1
        processed = processed + 1
    end
    bank.ISA_simulationHour = start
    ISA.debugLog("Catch-up x=%s y=%s z=%s from=%.3f through=%.3f target=%.3f segments=%d remainingHours=%.3f",
        tostring(bank.x), tostring(bank.y), tostring(bank.z), initialHour, start, now, processed, now - start)
    return start
end

function Native.update(generator, now)
    local system = ISA.PBSystem_Server
    if not system then return end
    local bank = system:getLuaObjectOnSquare(generator:getSquare())
    if not bank then
        system:loadIsoObject(generator)
        bank = system:getLuaObjectOnSquare(generator:getSquare())
    end
    if not bank then return end

    local drain = 0
    if bank:shouldDrain(generator) then
        bank:updateDrain()
        drain = bank.drain
    end
    local processedHour = Native.advance(bank, now, drain)
    if not processedHour then return end
    if processedHour == now then
        bank:updateBatteries(generator:getContainer(), bank.maxcapacity > 0 and bank.charge / bank.maxcapacity or 0)
        bank:updateGenerator()
        bank:updateSprite()
        bank:updateConGenerator()
    end
    bank:saveData(true)
    local interval = SandboxVars.ISA.ChargeFreq == 1 and 1 / 6 or 1
    generator:completeUpdate(processedHour, interval)
    ISA.debugLog("Update acknowledged x=%s y=%s z=%s charge=%.3f capacity=%.3f panels=%d drain=%.3f supply=%s nextHour=%.3f",
        tostring(bank.x), tostring(bank.y), tostring(bank.z), bank.charge, bank.maxcapacity,
        bank.npanels, drain, tostring(bank.on and bank.charge > 0), processedHour + interval)
end

function Native.start()
    if started then return end
    started = true
    Hook.OnPowerBankUpdate.Add(Native.update)
    Events.EveryTenMinutes.Add(Native.recordProduction)
    Events.OnSGlobalObjectSystemInit.Add(Native.recordProduction)
    ISA.debugLog("Subscribed Hook.OnPowerBankUpdate; shared production recorder ready")
end

return Native
