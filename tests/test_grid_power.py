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

if __name__=='__main__': unittest.main()
