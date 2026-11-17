local ISA = require "ImmersiveSolarArrays/Utilities"

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "ISA" then return end

    if command == "PlugBackupGenerator" then
        if type(args)~="table" or not ISA.PBSystem_Server then return end
        ISA.PBSystem_Server.Commands.plugGenerator(player,{gen={x=args.genX,y=args.genY,z=args.genZ},
            pbList={{x=args.pbX,y=args.pbY,z=args.pbZ}},plug=args.plug})
    end

    if command == "DebugPrint" then
        local text = args.text
        print("[ISA Server] .. " .. text)
    end

    if command == "SyncPowerBank" then
        if not args or not args.x or not args.y or not args.z then return end
        local square = getSquare(args.x, args.y, args.z)
        if not square or not ISA.PBSystem_Server then return end
        local isoObject = ISA.PBSystem_Server:getIsoObjectOnSquare(square) or ISA.WorldUtil.findTypeOnSquare(square, "PowerBank")
        if isoObject then
            if not instanceof(isoObject, "IsoGenerator") or
                (ISA.nativePowerBanks and not instanceof(isoObject, "IsoPowerBank")) then
                isoObject = ISA.WorldUtil.replaceIsoObjectWithGenerator(isoObject)
            end
            if isoObject and ISA.PBSystem_Server:isValidIsoObject(isoObject) then
                ISA.PBSystem_Server:loadIsoObject(isoObject)
            end
        end
    end

end)
