"""B42 mains eligibility and stale hydro-flag energy regressions."""
from pathlib import Path
import unittest
import test_power_budget as budget_fixture

ROOT=Path(__file__).resolve().parents[1]/'ApocalipseBR-ISA/42/media/lua'

class GridPowerTest(unittest.TestCase):
    def setUp(self):
        fixture=budget_fixture.PowerBudgetTest()
        fixture.setUp()
        self.lua,self.native=fixture.lua,fixture.native
        self.lua.execute('''
            Grid=require 'ImmersiveSolarArrays/GridPower'
            function getWorld() return {isHydroPowerOn=function() return true end} end
            square={x=1,outside=false,noPower=false}
            function square:isOutside() return self.outside end
            function square:isNoPower() return self.noPower end
            function square:hasGridPower() return not self.noPower and getSandboxOptions():doesPowerGridExist() end
        ''')

    def test_reported_generation_and_consumption_drain_after_grid_shutoff(self):
        self.lua.execute('''
            gridDay=1; now=240
            history.samples={{hour=0,output=145,hydro=true}}
            local b,g=makeBank(1,239)
            b.charge=500; b.maxcapacity=1000; b.drain=280
            b.ISA_energyConfig={on=true,drain=280,npanels=1,maxcapacity=1000,indoors=true}
            function g:getSquare() return square end
            Native.update(g,now)
            assert(b.charge==365 and b.ISA_energyConfig.gridEligible)
            assert(b.ISA_simulationHour==240 and b.ISA_supply.powered)
            Native.recordProduction()
            assert(history.samples[history.last].hydro==false)
        ''')

    def test_catchup_splits_at_shutoff_inside_compacted_legacy_sample(self):
        self.lua.execute('''
            gridDay=1
            history.samples={{hour=0,output=0,hydro=true}}
            local b=makeBank(1,23)
            b.charge=50; b.drain=10
            b.ISA_energyConfig={gridEligible=true}
            Native.advance(b,25,10)
            assert(b.charge==40 and b.ISA_simulationHour==25)
        ''')

    def test_no_power_room_cannot_suppress_drain_before_global_shutoff(self):
        self.lua.execute('''
            now=1; gridDay=30
            square.noPower=true
            assert(Grid.exists() and not Grid.current(square) and not Grid.eligible(square))
            history.samples={{hour=0,output=0,hydro=true}}
            local b,g=makeBank(1,0)
            function g:getSquare() return square end
            b.ISA_energyConfig={on=true,drain=2,npanels=1,maxcapacity=100,indoors=true,gridEligible=true}
            Native.update(g,1)
            assert(not b.ISA_energyConfig.gridEligible)
            Native.update(g,2)
            assert(b.charge==48)
        ''')

    def test_time_since_apocalypse_offsets_historical_shutoff(self):
        self.lua.execute('''
            timeSinceApo=2; gridDay=35
            assert(Grid.cutoffHour()==120)
            now=121
            assert(not Grid.exists())
        ''')

    def test_client_drain_uses_square_grid_without_generator_feedback(self):
        self.lua.execute('''
            package.loaded['Map/CGlobalObject']=true
            CGlobalObject={derive=function() return {} end}
        ''')
        cls=self.lua.execute((ROOT/'client/ImmersiveSolarArrays/Powerbank/PowerBankObject_Client.lua').read_text(encoding='utf-8'))
        self.lua.globals().ClientBank=cls
        self.lua.execute('''
            local b={on=true,getSquare=function() return square end}
            now=240; gridDay=1
            assert(ClientBank.shouldDrain(b))
            now=0
            assert(not ClientBank.shouldDrain(b))
            square.noPower=true
            assert(ClientBank.shouldDrain(b))
            b.conGenerator={ison=true}
            assert(not ClientBank.shouldDrain(b))
        ''')

    def test_indoor_bank_still_pays_native_residual_load_while_grid_exists(self):
        self.lua.execute('''
            now=323; gridDay=14
            history.samples={{hour=0,output=145,hydro=true}}
            local b,g=makeBank(1,322)
            b.charge=900; b.maxcapacity=1000; b.drain=230.560
            b.ISA_energyConfig={on=true,drain=230.560,npanels=1,maxcapacity=1000,indoors=true,gridEligible=true}
            function g:getSquare() return square end
            Native.update(g,now)
            assert(Grid.current(square) and b.ISA_energyConfig.gridEligible)
            assert(not Grid.coversLoad(b.drain,true))
            assert(math.abs(b.charge-814.440)<0.00001)
        ''')

    def test_local_grid_cannot_block_backup_for_generator_dependent_loads(self):
        self.lua.execute('''
            now=323; gridDay=14
            history.samples={{hour=0,output=0,hydro=true}}
            local b,g=makeBank(1,322)
            b.charge=0; b.maxcapacity=1000; b.drain=230.560
            b.conGenerator={x=2,y=0,z=0}
            b.ISA_energyConfig={on=true,drain=b.drain,npanels=1,maxcapacity=1000,indoors=true,gridEligible=true}
            b.ISA_backup={managed=true,ison=false,fuel=5,condition=90,rate=1,failsafe=true}
            function g:getSquare() return square end
            Native.update(g,now)
            assert(b.ISA_backup.ison and b.ISA_backup.fuel==4)
            assert(b.ISA_backupStatus.state=='running_waiting')
        ''')

    def test_idle_floor_is_exempt_only_when_grid_is_available(self):
        self.lua.execute('''
            assert(Grid.coversLoad(16,true))
            assert(not Grid.coversLoad(16,false))
            assert(not Grid.coversLoad(16.16,true))
            SandboxVars.ISA.DrainCalc=1
            assert(Grid.coversLoad(0,true))
            assert(not Grid.coversLoad(2,true))
        ''')

    def test_client_does_not_exempt_residual_appliance_load(self):
        self.lua.execute('''
            package.loaded['Map/CGlobalObject']=true
            CGlobalObject={derive=function() return {} end}
        ''')
        cls=self.lua.execute((ROOT/'client/ImmersiveSolarArrays/Powerbank/PowerBankObject_Client.lua').read_text(encoding='utf-8'))
        self.lua.globals().ClientBank=cls
        self.lua.execute('''
            now=323; gridDay=14
            local b={on=true,drain=230.560,getSquare=function() return square end}
            assert(Grid.current(square) and ClientBank.shouldDrain(b))
            b.drain=16
            assert(not ClientBank.shouldDrain(b))
        ''')

    def test_custom_consumption_scan_excludes_only_mains_powered_objects(self):
        self.lua.execute('''
            function instanceof(object,class) return object.kind==class end
            ItemContainer={isObjectPowered=function(object,includeGenerators)
                assert(includeGenerators==false); return object.mains
            end}
            local function fridge(mains)
                return {mains=mains,kind='IsoObject',getContainerCount=function() return 1 end,
                    getContainerByIndex=function() return {getType=function() return 'fridge' end} end}
            end
            local objects={fridge(true),fridge(false)}
            function square:getObjects() return {size=function() return #objects end,get=function(self,i) return objects[i+1] end} end
            function square:getX() return 0 end
            function square:getY() return 0 end
            function square:getZ() return 0 end
            function square:getCell() return {getGridSquare=function(self,x,y,z) if x==0 and y==0 and z==0 then return square end end} end
            IsoUtils={DistanceToSquared=function(x,y,x2,y2) return (x-x2)^2+(y-y2)^2 end}
        ''')
        scan=self.lua.execute((ROOT/'server/ImmersiveSolarArrays/PowerBank/SolarScan.lua').read_text(encoding='utf-8'))
        consumption=scan(self.lua.globals().square,False,True,False,0)
        self.assertAlmostEqual(consumption,46)

if __name__=='__main__': unittest.main()
