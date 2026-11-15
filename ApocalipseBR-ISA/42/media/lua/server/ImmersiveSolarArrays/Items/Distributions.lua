-- Native loot registrations only: no coordinate queue or room-discovery spawns.
require "Items/Distributions"
require "Items/ProceduralDistributions"
require "Vehicles/VehicleDistributions"

local ISA = require "ImmersiveSolarArrays/Utilities"
local Loot = {}
ISA.Distributions = Loot

-- Weights are relative loot weights, not percentages.
local definitions = {
    {
        fullType = "ISA.ISAMag1", multiplier = "LRMMisc",
        targets = {
            { "procedural", "BookstoreBooks", 1.0 },
            { "procedural", "BookstoreMisc", 0.5 },
            { "procedural", "CrateMagazines", 1.0 },
            { "procedural", "ElectronicStoreMagazines", 2.0 },
            { "procedural", "EngineerTools", 0.2 },
            { "procedural", "LibraryBooks", 0.8 },
            { "procedural", "LivingRoomShelf", 0.5 },
            { "procedural", "LivingRoomShelfNoTapes", 0.5 },
            { "procedural", "MagazineRackMixed", 0.6 },
            { "procedural", "PostOfficeBooks", 0.5 },
            { "procedural", "PostOfficeMagazines", 0.8 },
            { "procedural", "ShelfGeneric", 0.2 },
            { "vehicle", "ElectricianTruckBed", 1.0 },
        },
    },
    {
        fullType = "ISA.SolarPanel", multiplier = "LRMSolarPanels",
        targets = {
            { "procedural", "ArmyHangarTools", 0.05 },
            { "procedural", "ArmyStorageElectronics", 0.10 },
            { "procedural", "CrateCarpentry", 0.05 },
            { "procedural", "CrateElectronics", 0.10 },
            { "procedural", "CrateFarming", 0.05 },
            { "procedural", "CrateMechanics", 0.10 },
            { "procedural", "CrateMetalwork", 0.05 },
            { "procedural", "CrateRandomJunk", 0.10 },
            { "procedural", "CrateTools", 0.05 },
            { "procedural", "ElectronicStoreAppliances", 0.10 },
            { "procedural", "ElectronicStoreMisc", 0.15 },
            { "procedural", "EngineerTools", 0.10 },
            { "procedural", "GarageMechanics", 0.10 },
            { "procedural", "GarageMetalwork", 0.05 },
            { "procedural", "GarageTools", 0.05 },
            { "procedural", "GigamartHouseElectronics", 0.10 },
            { "procedural", "GigamartFarming", 0.05 },
            { "procedural", "LoggingFactoryTools", 0.05 },
            { "procedural", "MechanicShelfElectric", 0.05 },
            { "procedural", "MechanicShelfMisc", 0.05 },
            { "procedural", "MetalShopTools", 0.05 },
            { "procedural", "StoreShelfElectronics", 0.20 },
            { "procedural", "ToolStoreFarming", 0.10 },
            { "procedural", "ToolStoreMetalwork", 0.10 },
            { "procedural", "ToolStoreMisc", 0.15 },
            { "procedural", "ToolStoreTools", 0.10 },
            { "procedural", "OtherGeneric", 0.10 },
            { "vehicle", "ElectricianTruckBed", 1.00 },
        },
    },
    {
        fullType = "ISA.DeepCycleBattery", multiplier = "LRMBatteries",
        targets = {
            { "procedural", "JanitorMisc", 0.15 },
            { "procedural", "StoreShelfElectronics", 0.15 },
            { "procedural", "MechanicShelfElectric", 0.15 },
            { "procedural", "StoreShelfMechanics", 0.20 },
            { "procedural", "CrateElectronics", 0.15 },
            { "procedural", "CrateMechanics", 0.15 },
            { "procedural", "ToolStoreTools", 0.15 },
            { "procedural", "ToolStoreMisc", 0.20 },
            { "procedural", "ArmyStorageElectronics", 0.15 },
            { "procedural", "ElectronicStoreMisc", 0.15 },
            { "procedural", "CrateRandomJunk", 0.15 },
            { "procedural", "CrateTools", 0.15 },
            { "procedural", "OtherGeneric", 0.15 },
            { "procedural", "GarageMechanics", 0.15 },
            { "procedural", "ToolStoreFarming", 0.15 },
            { "procedural", "CrateFarming", 0.03 },
            { "procedural", "CrateMetalwork", 0.03 },
            { "vehicle", "ElectricianTruckBed", 1.00 },
        },
    },
    {
        fullType = "ISA.SuperBattery", multiplier = "LRMBatteries",
        targets = {
            { "procedural", "JanitorMisc", 0.05 },
            { "procedural", "StoreShelfElectronics", 0.05 },
            { "procedural", "MechanicShelfElectric", 0.05 },
            { "procedural", "StoreShelfMechanics", 0.10 },
            { "procedural", "CrateElectronics", 0.05 },
            { "procedural", "CrateMechanics", 0.05 },
            { "procedural", "ToolStoreTools", 0.05 },
            { "procedural", "ToolStoreMisc", 0.10 },
            { "procedural", "ArmyStorageElectronics", 0.20 },
            { "procedural", "ElectronicStoreMisc", 0.05 },
            { "procedural", "CrateRandomJunk", 0.05 },
            { "procedural", "CrateTools", 0.05 },
            { "procedural", "OtherGeneric", 0.05 },
            { "procedural", "GarageMechanics", 0.05 },
            { "procedural", "ToolStoreFarming", 0.05 },
            { "procedural", "CrateFarming", 0.05 },
            { "procedural", "CrateMetalwork", 0.05 },
            { "vehicle", "ElectricianTruckBed", 0.40 },
        },
    },
    {
        fullType = "ISA.ISAInverter", multiplier = "LRMMisc",
        targets = {
            { "procedural", "StoreShelfElectronics", 0.10 },
            { "procedural", "StoreShelfMechanics", 0.10 },
            { "procedural", "CrateElectronics", 0.10 },
            { "procedural", "CrateMechanics", 0.10 },
            { "procedural", "MechanicShelfMisc", 0.10 },
            { "procedural", "MechanicShelfElectric", 0.10 },
            { "procedural", "ToolStoreMisc", 0.10 },
            { "procedural", "ToolStoreTools", 0.10 },
            { "procedural", "GigamartHouseElectronics", 0.10 },
            { "procedural", "ArmyStorageElectronics", 0.10 },
            { "procedural", "ElectronicStoreMisc", 0.10 },
            { "procedural", "CrateRandomJunk", 0.10 },
            { "procedural", "CrateTools", 0.10 },
            { "procedural", "OtherGeneric", 0.10 },
            { "procedural", "GarageMechanics", 0.10 },
            { "procedural", "ElectronicStoreAppliances", 0.10 },
            { "procedural", "ToolStoreFarming", 0.10 },
            { "procedural", "CrateFarming", 0.03 },
            { "procedural", "CrateMetalwork", 0.03 },
            { "vehicle", "ElectricianTruckBed", 0.60 },
        },
    },
    {
        fullType = "ISA.SolarFailsafe", multiplier = "LRMMisc",
        targets = {
            { "procedural", "CrateElectronics", 0.01, "junk" },
            { "procedural", "GigamartHouseElectronics", 0.01, "junk" },
            { "procedural", "ArmyStorageElectronics", 0.01, "junk" },
            { "procedural", "ElectronicStoreMisc", 0.01, "junk" },
            { "vehicle", "ElectricianTruckBed", 0.01 },
        },
    },
    {
        fullType = "ISA.PowerBank", multiplier = "BatteryBankSpawn",
        targets = {
            { "procedural", "CrateGenerator", 2.0, "junk" },
            { "procedural", "GeneratorRoom", 0.20 },
            { "procedural", "CrateElectronics", 0.10 },
            { "procedural", "CrateTools", 0.05 },
            { "procedural", "GarageTools", 0.05 },
            { "procedural", "ElectronicStoreAppliances", 0.15 },
            { "vehicle", "ElectricianTruckBed", 0.10 },
        },
    },
}

local registered = false
local weights = {}
local bankMultipliers = { 0, 0.3, 1, 3 }

local function trackItems(items)
    for i = 1, #items, 2 do
        for _, definition in ipairs(definitions) do
            if items[i] == definition.fullType then
                weights[#weights + 1] = { items = items, index = i + 1, base = items[i + 1], multiplier = definition.multiplier }
                break
            end
        end
    end
end

function Loot.register()
    if registered then return end
    local pdList = ProceduralDistributions.list
    local subDist = SuburbsDistributions

    pdList.ISABatteries = {
        rolls = 4,
        items = {
            "ISA.DeepCycleBattery", 36,
            "ISA.SuperBattery", 8,
            "ISA.DIYBattery", 8,
            "ISA.WiredCarBattery", 8,
        }
    }
    pdList.ISABatteriesCache = {
        rolls = 4,
        items = {
            "ISA.DeepCycleBattery", 64,
            "ISA.SuperBattery", 32,
            "ISA.DIYBattery", 32,
            "ISA.WiredCarBattery", 32,
        }
    }
    pdList.ISASolarBox = {
        rolls = 4,
        items = {
            "ISA.SolarPanel", 48,
            "ISA.DeepCycleBattery", 48,
            "ISA.SuperBattery", 24,
        },
        junk = {
            rolls = 1,
            items = {
                "ISA.ISAMag1", 64,
                "ISA.ISAInverter", 64,
                "ISA.SolarPanel", 16,
                "ISA.DeepCycleBattery", 16,
                "ISA.SuperBattery", 16,
                "ISA.SolarFailsafe", 0.1,
                "Base.ElectronicsScrap", 20,
                "Base.MetalBar", 10,
                "Base.SmallSheetMetal", 10,
                "Base.Screws", 5,
                "Base.ElectricWire", 20,
                "Base.RemoteCraftedV3", 0.1,
            }
        }
    }

    ----------------------------------------------------------------------------------------------------------------------
    ---edit procList tables for room / cache house types

    subDist.all.BatteryBank = {
        procedural = true,
        procList = {
            {name="ISABatteries", min=0, max=99},
        },
    }
    subDist.all.SolarBox = {
        procedural = true,
        procList = {
            { name = "ISASolarBox", min = 0, max = 99, weightChance = 80 },
            { name = "ISABatteries", min = 0, max = 99, weightChance = 20 },
            { name = "ISABatteriesCache", min = 0, max = 99, weightChance = 10 },
        },
    }

    -- Native annotated-map stashes remain opt-in; the engine fills these containers.
    subDist.ISASolarBoxCache = copyTable(subDist.electronicsstorage or {})
    subDist.ISASolarBoxCache.isStore = nil
    subDist.ISASolarBoxCache.SolarBox = copyTable(pdList.ISASolarBox)
    subDist.ISASolarBoxCache.SolarBox.rolls = 32

    for _, definition in ipairs(definitions) do
        for _, target in ipairs(definition.targets) do
            local source = target[1] == "vehicle" and VehicleDistributions or pdList
            local distribution = source[target[2]]
            if distribution and target[4] then distribution = distribution[target[4]] end
            local items = distribution and distribution.items
            if items then
                items[#items + 1] = definition.fullType
                items[#items + 1] = target[3]
                weights[#weights + 1] = { items = items, index = #items, base = target[3], multiplier = definition.multiplier }
            else
                print("[ISA] Missing optional loot target: " .. target[1] .. "/" .. target[2] .. (target[4] and "/" .. target[4] or ""))
            end
        end
    end

    for _, name in ipairs({ "ISABatteries", "ISABatteriesCache", "ISASolarBox" }) do
        local distribution = pdList[name]
        trackItems(distribution.items)
        if distribution.junk then trackItems(distribution.junk.items) end
    end
    local stash = subDist.ISASolarBoxCache.SolarBox
    trackItems(stash.items)
    if stash.junk then trackItems(stash.junk.items) end
    registered = true
end

-- Used by the existing native annotated-map registration.
function Loot.insertItemsToMultipleLists(distributions, names, items)
    for _, name in ipairs(names) do
        local distribution = distributions[name]
        if distribution and distribution.items then
            for _, value in ipairs(items) do
                table.insert(distribution.items, value)
            end
        end
    end
end

function Loot.applySandboxWeights()
    -- SandboxOptions.load follows distribution merging in the inspected engine.
    -- Apply server options here, once startup has reached OnLoadedMapZones.
    local sandbox = SandboxVars.ISA or {}
    for _, entry in ipairs(weights) do
        local multiplier
        if entry.multiplier == "BatteryBankSpawn" then
            multiplier = bankMultipliers[sandbox.BatteryBankSpawn or 3] or 1
        else
            multiplier = sandbox[entry.multiplier]
            if type(multiplier) ~= "number" then multiplier = 1 end
        end
        entry.items[entry.index] = entry.base * multiplier
    end
    -- Coalesce the existing annotated-map reparse into this startup pass.
    ItemPickerJava.doParse = nil
    ItemPickerJava.Parse()
end

Events.OnPostDistributionMerge.Add(Loot.register)
Events.OnLoadedMapZones.Add(Loot.applySandboxWeights)

return Loot
