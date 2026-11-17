"""Exercise the production server callback and catch-up history with Lua 5.1."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/PowerBank/NativeSimulation.lua"


class NativeSimulationTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            ISA = {}
            logs = {}
            print = function(message) logs[#logs+1] = message end
            package.loaded['ImmersiveSolarArrays/Utilities'] = ISA
            function isClient() return false end
            now = 0
            function getTimestampMs() return 0 end
            function getWorld() return {isHydroPowerOn=function() return false end} end
            gridDay=-1
            timeSinceApo=1
            function getSandboxOptions() return {
                doesPowerGridExist=function() return now/24+(timeSinceApo-1)*30<=gridDay end,
                getElecShutModifier=function() return gridDay end,
                getTimeSinceApo=function() return timeSinceApo end
            } end
            function ZombRand() return 1 end
            PowerBankBackup={enable=function() end}
            function getGameTime() return { getWorldAgeHours = function() return now end } end
            SandboxVars = { ISA = { ChargeFreq = 1 } }
            history = { samples = {} }
            ModData = { getOrCreate = function() return history end }
            subscribed = {}
            local function event(name)
                return { Add = function(fn) subscribed[name] = fn end }
            end
            Hook = { OnPowerBankUpdate = event('update'),OnPowerBankBackupUpdate=event('backup') }
            Events = {
                EveryTenMinutes = event('production'),
                OnSGlobalObjectSystemInit = event('initial')
            }
            Events.OnTick=event('queue')
            ISA.PBSystem_Server = { getModifiedSolarOutput = function() return 10 end }
            function isServer() return true end
            IsoPowerBank = {}
            ISBaseObject = { derive = function() return {} end }
            Events.OnGameTimeLoaded = { Add = function() end }
            Events.OnInitSeasons = { Add = function() end }
        """)
        system = self.lua.globals().ISA.PBSystem_Server
        utility = ROOT / 'ApocalipseBR-ISA/42/media/lua/shared/ImmersiveSolarArrays/Utilities.lua'
        isa = self.lua.execute(utility.read_text(encoding='utf-8'))
        isa.PBSystem_Server = system
        self.lua.globals().ISA = isa
        self.lua.globals().package.loaded['ImmersiveSolarArrays/Utilities'] = isa
        grid=ROOT/'ApocalipseBR-ISA/42/media/lua/shared/ImmersiveSolarArrays/GridPower.lua'
        self.lua.globals().package.loaded['ImmersiveSolarArrays/GridPower']=self.lua.execute(grid.read_text(encoding='utf-8'))
        for name in ('ProductionHistory','EnergyModel'):
            path=SOURCE.parent / (name+'.lua')
            module=self.lua.execute(path.read_text(encoding='utf-8'))
            self.lua.globals().package.loaded['ImmersiveSolarArrays/PowerBank/'+name]=module
        self.native = self.lua.execute(SOURCE.read_text(encoding="utf-8"))

    def test_debug_logging_obeys_live_sandbox_flag(self):
        self.native.recordProduction()
        self.assertEqual(len(self.lua.globals().logs), 0)
        self.lua.globals().SandboxVars.ISA.Debug = True
        self.native.start()
        self.lua.globals().now = 1
        self.native.recordProduction()
        messages = list(self.lua.globals().logs.values())
        self.assertTrue(any('Subscribed budgeted' in message for message in messages))
        count = len(messages)
        self.lua.globals().SandboxVars.ISA.Debug = False
        self.lua.globals().now = 2
        self.native.recordProduction()
        self.assertEqual(len(self.lua.globals().logs), count)

    def test_production_is_shared_and_deduplicated(self):
        self.native.recordProduction()
        self.native.recordProduction()
        self.assertEqual(len(self.lua.globals().history.samples), 1)
        self.lua.globals().now = 1
        self.native.recordProduction()
        self.assertEqual(len(self.lua.globals().history.samples), 1)

    def test_capacity_clamping_applies_at_each_day_night_interval(self):
        self.lua.execute("""
            history.samples = {
                {hour=0, output=10}, {hour=1, output=0}, {hour=2, output=20}
            }
            bank = { ISA_simulationHour=0, charge=5, maxcapacity=10, npanels=1,on=true,drain=6 }
        """)
        bank = self.lua.globals().bank
        self.assertEqual(self.native.advance(bank, 3, 6)[0], 3)
        self.assertEqual(bank.charge, 10)
        self.assertEqual(bank.ISA_simulationHour, 3)
        self.native.advance(bank, 3, 6)
        self.assertEqual(bank.charge, 10)

    def test_long_catchup_has_a_bounded_batch_and_resumes(self):
        self.lua.execute("""
            for i=0,300 do history.samples[#history.samples+1] = {hour=i,output=1} end
            bank = { ISA_simulationHour=0, charge=0, maxcapacity=1000, npanels=1 }
        """)
        bank = self.lua.globals().bank
        self.assertEqual(self.native.advance(bank, 300, 0)[0], 32)
        self.assertEqual(self.native.advance(bank, 300, 0)[0], 64)
        while bank.ISA_simulationHour<300: self.native.advance(bank,300,0)
        self.assertEqual(bank.charge, 300)

    def test_start_subscribes_one_callback_and_one_shared_recorder(self):
        self.native.start()
        self.assertEqual(set(self.lua.globals().subscribed.keys()), {'update', 'production', 'initial','queue','backup'})

    def test_reconstruction_preserves_the_existing_battery_container(self):
        self.lua.execute("""
            ISA.nativePowerBanks = true
            function instanceof(object, name)
                return object.kind == name or name == 'IsoGenerator' and object.kind == 'IsoPowerBank'
            end
            local objects = {}
            local function list()
                return { size=function() return #objects end, get=function(self,index) return objects[index+1] end }
            end
            square = {
                getCell=function() return {} end,
                getSpecialObjects=list,
                getObjects=list,
                transmitRemoveItemFromSquare=function() end,
                AddSpecialObject=function(self,object) objects[#objects+1]=object end
            }
            container = {
                setParent=function(self,value) self.parent=value end,
                setSourceGrid=function(self,value) self.source=value end,
                battery='existing battery identity'
            }
            original = { kind='IsoGenerator', data={ charge=7 } }
            function original:getSquare() return square end
            function original:getSprite() return {name='solarmod_tileset_01_0'} end
            function original:getModData() return self.data end
            function original:getContainer() return container end
            function original:removeFromWorld() end
            function original:removeFromSquare() objects={} end
            objects[1]=original
            IsoPowerBank = { new=function()
                local bank={ kind='IsoPowerBank',data={} }
                function bank:getModData() return self.data end
                function bank:setSprite(sprite) self.sprite=sprite end
                function bank:setSquare(value) self.square=value end
                function bank:getSquare() return self.square end
                function bank:setContainer(value) self.container=value end
                function bank:createContainersFromSpriteProperties() assert(self.container==container) end
                function bank:transmitCompleteItemToClients() end
                return bank
            end }
        """)
        source = ROOT / 'ApocalipseBR-ISA/42/media/lua/shared/ImmersiveSolarArrays/WorldUtilities.lua'
        self.lua.execute(source.read_text(encoding='utf-8'))
        self.lua.execute("""
            resolved = ISA.WorldUtil.replaceIsoObjectWithGenerator(original)
            assert(resolved.kind=='IsoPowerBank')
            assert(resolved.container==container and container.parent==resolved and container.source==square)
            assert(resolved.data.charge==7 and resolved.data.ApocBRPowerBank==true)
            assert(ISA.WorldUtil.replaceIsoObjectWithGenerator(resolved)==resolved)
            assert(square.getObjects():size()==1)
        """)

    def test_callback_applies_and_acknowledges_once(self):
        self.lua.execute("""
            now = 1
            history.samples = { {hour=0, output=10} }
            writes, applied, saved, acknowledged = 0, 0, 0, 0
            bank = { ISA_simulationHour=0, charge=0, maxcapacity=20, npanels=1,on=false,drain=0 }
            function bank:calculateBatteryStats() end
            function bank:updateDrain() end
            function bank:getConGenerator() end
            function bank:shouldDrain() return false end
            function bank:updateBatteries(container, fraction) writes=writes+1; assert(fraction==0.5) end
            function bank:updateGenerator() applied=applied+1 end
            function bank:updateSprite() end
            function bank:updateConGenerator() end
            function bank:saveData() saved=saved+1 end
            function ISA.PBSystem_Server:getLuaObjectOnSquare() return bank end
            generator = {
                getSquare = function() return {isOutside=function() return true end} end,
                getContainer = function() return {} end,
                prepareSimulationUpdate=function() end,
                completeUpdate = function(self, through, interval)
                    assert(through==1 and interval==1/6); acknowledged=acknowledged+1
                end
            }
        """)
        self.native.update(self.lua.globals().generator, 1)
        for key in ('writes', 'applied', 'saved', 'acknowledged'):
            self.assertEqual(self.lua.globals()[key], 1)


if __name__ == '__main__':
    unittest.main()
