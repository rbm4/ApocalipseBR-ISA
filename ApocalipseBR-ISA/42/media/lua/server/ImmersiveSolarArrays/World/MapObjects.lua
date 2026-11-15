local ISA = require "ImmersiveSolarArrays/Utilities"

if isClient() then

    ---update isoObjects when chunk loads
    local function LoadPowerbank(isoObject)
        if not isoObject then return end
        local container = isoObject:getContainer()
        if not container and isoObject.createContainersFromSpriteProperties then
            isoObject:createContainersFromSpriteProperties()
            container = isoObject:getContainer()
        end
        if container and container.setAcceptItemFunction then
            container:setAcceptItemFunction("AcceptItemFunction.ISA_Batteries")
        end
    end
    MapObjects.OnLoadWithSprite("solarmod_tileset_01_0", LoadPowerbank, 6)

else

    ---update isoObjects when chunk loads
    local function LoadPowerbank(isoObject)
        if not isoObject then return end
        if not instanceof(isoObject, "IsoGenerator") then
            isoObject = ISA.WorldUtil.replaceIsoObjectWithGenerator(isoObject)
            if not isoObject then return end
        end
        ISA.PBSystem_Server:loadIsoObject(isoObject)
        local container = isoObject:getContainer()
        if not container and isoObject.createContainersFromSpriteProperties then
            isoObject:createContainersFromSpriteProperties()
            container = isoObject:getContainer()
        end
        if container and container.setAcceptItemFunction then
            container:setAcceptItemFunction("AcceptItemFunction.ISA_Batteries")
        end
    end
    MapObjects.OnLoadWithSprite("solarmod_tileset_01_0", LoadPowerbank, 6)

    ---update isoObjects when chunk loads first time
    local function OnNewWithSprite(isoObject)
        local isaType = ISA.WorldUtil.getType(isoObject)
        local square = isoObject:getSquare()
        if not square then error("ISA: OnNewWithSprite no square") return end

        if isaType == "PowerBank" then
            -- Map-authored banks still use the normal bank lifecycle. Random
            -- equipment now comes from native container/vehicle loot tables.
            LoadPowerbank(isoObject)
        else
            square:getSpecialObjects():add(isoObject)
        end
    end

    local MapObjects = MapObjects
    for sprite, type in pairs(ISA.WorldUtil.ISATypes) do
        MapObjects.OnNewWithSprite(sprite, OnNewWithSprite, 5)
    end

end
