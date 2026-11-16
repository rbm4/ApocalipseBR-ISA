"""Budget, persistence and chronological energy regression cases using production Lua."""
import unittest
import test_native_simulation as native_fixture

class PowerBudgetTest(unittest.TestCase):
    def setUp(self):
        fixture=native_fixture.NativeSimulationTest()
        fixture.setUp()
        self.lua,self.native=fixture.lua,fixture.native
        self.lua.globals().Native=self.native
        self.lua.execute('''
            banks={}
            function ISA.PBSystem_Server:getLuaObjectAt(x) return banks[x] end
            function ISA.PBSystem_Server:getLuaObjectOnSquare(square) return banks[square.x] end
            function makeBank(x,hour)
                local b={x=x,y=0,z=0,on=true,drain=2,npanels=1,maxcapacity=100,charge=50,ISA_simulationHour=hour}
                local square={x=x,isOutside=function() return true end}
                local g={}
                function g:getSquare() return square end
                function g:getObjectIndex() return 0 end
                function g:deferUpdate() self.deferred=true end
                function g:prepareSimulationUpdate() end
                function g:checkpointUpdate(hour) self.checkpoint=hour end
                function g:completeUpdate(hour) self.completed=hour end
                function g:failScheduledUpdate() self.failed=true end
                function g:getContainer() return {} end
                function b:getIsoObject() return g end
                function b:getConGenerator() return nil end
                function b:updateDrain() end
                function b:updateBatteries() end
                function b:updateGenerator() end
                function b:updateSprite() end
                b.broadcasts,b.checkpoints=0,0
                function b:saveData(transmit)
                    if transmit then self.broadcasts=self.broadcasts+1 else self.checkpoints=self.checkpoints+1 end
                end
                banks[x]=b
                return b,g
            end
        ''')

    def test_global_quota_fair_service_and_coalescing(self):
        self.lua.execute('''
            for i=0,1000 do history.samples[i+1]={hour=i,output=i%2*4} end
            now=1000
            for i=1,20 do local b,g=makeBank(i,0); Native.request(g); Native.request(g) end
            for i=21,22 do local b,g=makeBank(i,999.9); Native.request(g) end
            assert(Native.metrics.pending==22)
            Native.processQueue()
            assert(Native.metrics.jobs<=8 and Native.metrics.steps<=256)
            assert(banks[21].broadcasts==1 and banks[22].broadcasts==1)
            assert(banks[1].checkpoints>0 and banks[1].broadcasts==0)
            for tick=1,150 do Native.processQueue() end
            for i=1,22 do assert(banks[i].ISA_simulationHour==now); assert(banks[i].broadcasts==1) end
            assert(Native.metrics.pending==0)
        ''')

    def test_time_guard_stops_between_jobs(self):
        self.lua.execute('''
            now=10
            history.samples={{hour=0,output=1}}
            for i=1,10 do local b,g=makeBank(i,0); Native.request(g) end
            local ms=0
            function getTimestampMs() ms=ms+1; return ms end
            Native.processQueue()
            assert(Native.metrics.jobs<=1 and Native.metrics.pending>=9)
        ''')

    def test_history_migration_is_incremental_and_marks_missing_energy(self):
        self.lua.execute('''
            for i=1,100000 do history.samples[i]={hour=i,output=i%2} end
            local H=require 'ImmersiveSolarArrays/PowerBank/ProductionHistory'
            local d=H.get()
            assert(d.first==95905 and d.last==100000)
            H.prune()
            assert(d.samples[128]==nil and d.samples[129]~=nil)
            local b=makeBank(1,0)
            b.charge=90
            Native.advance(b,95905,2)
            assert(b.charge==0 and b.ISA_historyLostUntil==95905 and b.ISA_simulationHour==95905)
            for i=1,800 do H.prune() end
            local count=0
            for k in pairs(d.samples) do count=count+1 end
            assert(count==4096)
            H.append(100001,99,false)
            assert(d.samples[d.first-1]==nil and d.last-d.first+1==4096)
        ''')

    def test_backup_exhaustion_switches_to_battery_at_correct_hour(self):
        self.lua.execute('''
            history.samples={{hour=0,output=0}}
            local b=makeBank(1,0)
            b.drain=4; b.charge=8
            b.ISA_backup={fuel=2,rate=1,condition=100,ison=true,wearChance=30}
            local through,steps=Native.advance(b,4,4)
            assert(through==4 and steps<=8)
            assert(b.ISA_backup.fuel==0 and not b.ISA_backup.ison and b.charge==0)
            local h=b.ISA_supply
            assert(h[h.last].hour==4 and not h[h.last].powered)
        ''')

    def test_failsafe_hysteresis_and_resumable_results(self):
        self.lua.execute('''
            history.samples={{hour=0,output=2}}
            local a=makeBank(1,0)
            local b=makeBank(2,0)
            for _,bank in ipairs({a,b}) do
                bank.charge=6; bank.maxcapacity=20; bank.drain=4
                bank.ISA_backup={fuel=10,rate=1,condition=100,ison=false,failsafe=true,wearChance=30}
            end
            Native.advance(a,6,4,100)
            local loops=0
            while b.ISA_simulationHour<6 do Native.advance(b,6,4,1); loops=loops+1; assert(loops<30) end
            assert(math.abs(a.charge-b.charge)<1e-6)
            assert(math.abs(a.ISA_backup.fuel-b.ISA_backup.fuel)<1e-6)
            assert(a.ISA_backup.fuel<10 and a.ISA_backup.fuel>0)
            assert(a.ISA_supply.last==1) -- no outage while either source supplies
        ''')

    def test_late_backup_observation_does_not_power_the_past(self):
        self.lua.execute('''
            history.samples={{hour=0,output=0}}
            local b=makeBank(1,0)
            b.charge=4; b.drain=2
            b.ISA_backup={fuel=10,rate=1,condition=100,ison=true,availableFrom=10}
            Native.advance(b,10,2)
            assert(b.charge==0 and b.ISA_backup.fuel==10)
        ''')

    def test_pending_inventory_is_applied_only_at_completed_boundary(self):
        self.lua.execute('''
            for i=0,100 do history.samples[i+1]={hour=i,output=0} end
            now=100
            local b,g=makeBank(1,0)
            Native.inventoryDelta(b,30,50)
            Native.processQueue()
            assert(b.ISA_pendingInventory and b.maxcapacity==100 and b.broadcasts==0)
            for i=1,10 do Native.processQueue() end
            assert(not b.ISA_pendingInventory and b.maxcapacity==150 and b.charge==30 and b.broadcasts==1)
        ''')

    def test_failed_job_restores_configuration_and_retries_without_spin(self):
        self.lua.execute('''
            now=10
            local b,g=makeBank(1,0)
            b.ISA_energyConfig={on=false,drain=7,npanels=1,maxcapacity=100}
            Native.request(g)
            local old=Native.advance
            Native.advance=function() error('fixture failure') end
            Native.processQueue()
            assert(b.on and b.drain==2 and not b._ISA_processing and g.failed)
            assert(Native.metrics.failures==1 and Native.metrics.pending==0)
            Native.advance=old
        ''')

    def test_observed_rate_change_does_not_refill_spent_fuel(self):
        self.lua.execute('''
            local M=require 'ImmersiveSolarArrays/PowerBank/EnergyModel'
            local b=makeBank(1,0)
            b.ISA_backup={fuel=3,condition=100,ison=true,rate=1}
            M.observe(b.ISA_backup,{hour=1,rate=2,wearChance=30,failsafe=false})
            history.samples={{hour=0,output=0}}
            Native.advance(b,2,2,100)
            assert(b.ISA_backup.fuel==0)
        ''')

    def test_virtual_bank_finishes_backup_fuel_once_and_keeps_checkpoint(self):
        self.lua.execute('''
            now=4
            history.samples={{hour=0,output=0}}
            local b,g=makeBank(1,0)
            b.charge=8; b.drain=4; b.conGenerator={x=5,y=0,z=0,ison=true}
            b.ISA_backup={fuel=2,condition=100,ison=true,rate=1,availableFrom=0,
                appliedFuel=2,appliedCondition=100,appliedOn=true,
                observedFuel=2,observedCondition=100,observedOn=true,observedRate=1,observedFailsafe=false}
            b.ISA_energyConfig={on=true,drain=4,npanels=1,maxcapacity=100}
            function b:getIsoObject() return nil end
            local source={fuel=2,condition=100,ison=true,commits=0}
            function source:getSquare() return {} end
            function source:getObjectIndex() return 0 end
            function source:getX() return 5 end
            function source:getY() return 0 end
            function source:getZ() return 0 end
            function source:getFuel() return self.fuel end
            function source:getCondition() return self.condition end
            function source:isActivated() return self.ison end
            function source:isConnected() return true end
            function source:getTotalPowerUsing() return 1 end
            function source:getGeneratorItemType() return 'Base.Generator' end
            function source:applyISABackupState(fuel,condition,ison)
                self.fuel,self.condition,self.ison=fuel,condition,ison; self.commits=self.commits+1
            end
            function b:getConGenerator() return source end
            PowerBankBackup.claim=function() return true end
            ISA.WorldUtil={findOnSquare=function() return nil end}
            ScriptManager={instance={getItem=function() return nil end}}
            Native.requestBackup(source,{x=1,y=0,z=0})
            for i=1,4 do Native.processQueue() end
            assert(source.fuel==0 and not source.ison and source.commits==1)
            assert(b.charge==0 and b.ISA_simulationHour==4 and b.broadcasts==1)
        ''')

    def test_pending_command_runs_once_after_catchup(self):
        self.lua.execute('''
            now=100
            for i=0,100 do history.samples[i+1]={hour=i,output=0} end
            local b,g=makeBank(1,0)
            local called=0
            ISA.PBSystem_Server.Commands={activatePowerbank=function(player,args)
                assert(b.ISA_simulationHour==now and args.activate==false)
                called=called+1
            end}
            Native.queueCommand(b,'activatePowerbank',{}, {activate=true})
            Native.queueCommand(b,'activatePowerbank',{}, {activate=false})
            Native.processQueue()
            assert(called==0)
            for i=1,10 do Native.processQueue() end
            assert(called==1 and not b._ISA_command)
        ''')

    def test_zero_capacity_failsafe_supplies_without_threshold_oscillation(self):
        self.lua.execute('''
            history.samples={{hour=0,output=0}}
            local b=makeBank(1,0)
            b.charge=0; b.maxcapacity=0; b.drain=4
            b.ISA_backup={fuel=3,rate=1,condition=100,ison=false,failsafe=true}
            local through,steps=Native.advance(b,2,4)
            assert(through==2 and steps<=4 and b.ISA_backup.ison and b.ISA_backup.fuel==1)
            assert(b.ISA_supply.powered)
        ''')

    def test_grid_supply_stops_failsafe_and_preserves_battery(self):
        self.lua.execute('''
            history.samples={{hour=0,output=0,hydro=true}}
            local b=makeBank(1,0)
            b.charge=2; b.ISA_energyConfig={indoors=true}
            b.ISA_backup={fuel=3,rate=1,condition=100,ison=true,failsafe=true}
            Native.advance(b,3,2)
            assert(b.charge==2 and b.ISA_backup.fuel==3 and not b.ISA_backup.ison)
            assert(b.ISA_supply.powered)
        ''')

    def test_refuel_observation_creates_outage_and_restoration_at_its_timestamp(self):
        self.lua.execute('''
            history.samples={{hour=0,output=0}}
            local M=require 'ImmersiveSolarArrays/PowerBank/EnergyModel'
            local b=makeBank(1,0)
            b.charge=0
            b.ISA_backup={fuel=1,rate=1,condition=100,ison=true}
            M.observe(b.ISA_backup,{hour=2,fuel=3,ison=true,rate=1,wearChance=30,failsafe=false})
            Native.advance(b,4,2)
            assert(b.ISA_backup.fuel==1)
            local h=b.ISA_supply
            assert(h.last==3 and h[2].hour==1 and not h[2].powered and h[3].hour==2 and h[3].powered)
        ''')

if __name__=='__main__': unittest.main()
