"""Managed backup authority, stop-before-release and runtime presentation."""
from pathlib import Path
import unittest
import test_power_bank_activation as activation_fixture
import test_power_budget as budget_fixture

ROOT=Path(__file__).resolve().parents[1]/'ApocalipseBR-ISA/42/media/lua'

class ManagedBackupTest(unittest.TestCase):
    def setUp(self):
        fixture=activation_fixture.PowerBankActivationTest()
        fixture.setUp()
        self.fixture=fixture
        self.lua=fixture.lua
        self.lua.execute('''
            function generator:getModData() self.data=self.data or {}; return self.data end
            function generator:getX() return 2 end
            function generator:getY() return 0 end
            function generator:getZ() return 0 end
        ''')

    def load_commands(self):
        self.lua.execute('''
            system.instance=system
            function system:noise() end
            function bank:getSquare() return square end
            function generator:isConnected() return true end
            function square:getGenerator() return generator end
            function getSquare() return square end
            package.loaded['ImmersiveSolarArrays/PowerBank/PowerBankSystem_Server']=system
        ''')
        self.lua.execute((ROOT/'server/ImmersiveSolarArrays/PowerBank/PowerBankSystem_Commands.lua').read_text(encoding='utf-8'))

    def test_timed_actions_reject_owned_generators_and_leave_normal_actions_working(self):
        self.lua.execute('''
            local called=0
            ISActivateGenerator={isValid=function() return true end,
                complete=function(self) called=called+1; self.generator.active=self.activate; return true end}
            ISPlugGenerator={isValid=function() return true end,complete=function() called=called+1; return true end}
            function system:onActivateGenerator() end
            ISA.queueFunction=function(event,fn) install=fn end
            function getCalls() return called end
        ''')
        self.lua.execute((ROOT/'shared/ImmersiveSolarArrays/Patches.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            install()
            local action={generator=generator,activate=true,character=character}
            generator:getModData().ApocBRISABackupOwner={x=0,y=0,z=0}
            assert(not ISActivateGenerator.isValid(action))
            assert(not ISActivateGenerator.complete(action) and getCalls()==0)
            action.plug=false
            assert(not ISPlugGenerator.isValid(action) and not ISPlugGenerator.complete(action))
            generator:getModData().ApocBRISABackupOwner=nil
            assert(ISActivateGenerator.isValid(action) and ISActivateGenerator.complete(action))
            assert(ISPlugGenerator.isValid(action) and ISPlugGenerator.complete(action) and getCalls()==2)
        ''')

    def test_disconnect_stops_before_releasing_and_wrong_target_is_ignored(self):
        self.lua.execute('''
            package.loaded['Map/SGlobalObject']=true
            package.loaded['ImmersiveSolarArrays/PowerBank/SolarScan']=function() return 0 end
            SGlobalObject={derive=function() return {} end}
            generator.active=true; generator.owned=true; generator.fuel=6; generator.condition=90
            function generator:getFuel() return self.fuel end
            function generator:getCondition() return self.condition end
            function generator:getISABackupOwner() return {x=0,y=0,z=0} end
            function generator:applyISABackupState(fuel,condition,on)
                assert(self.owned); self.fuel,self.condition,self.active=fuel,condition,on
            end
            PowerBankBackup={isControlled=function(g) return g.owned end,release=function(g)
                assert(not g.active); g.owned=false
            end}
        ''')
        cls=self.lua.execute((ROOT/'server/ImmersiveSolarArrays/PowerBank/PowerBankObject_Server.lua').read_text(encoding='utf-8'))
        self.lua.globals().BankClass=cls
        self.lua.execute('''
            bank.conGenerator={x=2,y=0,z=0,ison=true}
            bank.ISA_backup={fuel=4,condition=85}
            function bank:getConGenerator() return generator end
            local wrong={getX=function() return 99 end,getY=function() return 0 end,getZ=function() return 0 end}
            assert(not BankClass.disconnectBackupGenerator(bank,wrong) and generator.active and generator.owned)
            assert(BankClass.disconnectBackupGenerator(bank,generator))
            assert(not generator.active and not generator.owned and generator.fuel==4 and generator.condition==85)
            assert(not bank.conGenerator and not bank.ISA_backup and not bank.ISA_backupStatus)
        ''')

    def test_disconnect_service_revalidates_proximity_and_source_association(self):
        self.load_commands()
        self.lua.execute('''
            local calls=0
            bank.conGenerator={x=2,y=0,z=0}
            function bank:disconnectBackupGenerator() calls=calls+1; self.conGenerator=false end
            local args={gen={x=99,y=0,z=0},pbList={{x=0,y=0,z=0}},plug=false}
            assert(not system.Commands.plugGenerator(character,args) and calls==0)
            args.gen.x=2
            character.x=100
            assert(not system.Commands.plugGenerator(character,args) and calls==0)
            character.x=0.5
            assert(system.Commands.plugGenerator(character,args) and calls==1)
            assert(not system.Commands.plugGenerator(character,args) and calls==1)
            ISA.NativeSimulation={}
            assert(not system.Commands.activateGenerator(character,{pb={x=0,y=0,z=0},activate=true}))
        ''')

    def test_details_display_authoritative_runtime_even_without_backup_square(self):
        self.fixture.load_details_view()
        self.lua.execute('''
            bank.conGenerator={x=100,y=100,z=0}
            bank.ISA_backupStatus={state='running_charging',failsafe=true,startPercent=2,stopPercent=4,fuelPercent=80,condition=90}
            function getSquare() error('Backup-square lookup is not needed to render runtime') end
            local view=setmetatable({width=600,parent={parent={luaPB=bank,playerObj=character}},
                devButton={setVisible=function() end},drawn={}}, {__index=ISA.StatusWindowDetailsView})
            function view:drawText(text,x,y,r,g,b) self.drawn[text]={r,g,b} end
            view.drawTextRight=view.drawText
            function view:drawRect() end
            function view:drawRectBorder() end
            function view:setHeightAndParentHeight() end
            view:render()
            assert(view.drawn.IGUI_ISABackup_RunningCharging and view.drawn.IGUI_ISABackup_Thresholds)
            assert(view.drawn.IGUI_ISABackup_FuelCondition and view.drawn.IGUI_ISABackup_ControlHint)
            local color=view.drawn.IGUI_ISABackup_RunningCharging
            assert(color[1]==0.2 and color[2]==0.85 and color[3]==0.35)
            assert(view.drawn.IGUI_ISABackup_Thresholds[1]==1)
            local Status=require 'ImmersiveSolarArrays/BackupStatus'
            local r,g,b=Status.color({conGenerator=false})
            assert(r==0.6 and g==0.6 and b==0.6)
        ''')

    def test_context_menu_disables_wrapped_controls_only_for_owned_source(self):
        self.lua.execute('''
            local color={getR=function() return 1 end,getG=function() return 1 end,getB=function() return 1 end}
            function getText(key) return key end
            function getCore() return {getGoodHighlitedColor=function() return color end,getBadHighlitedColor=function() return color end} end
            Events={OnPreFillWorldObjectContextMenu={Add=function() end},OnFillWorldObjectContextMenu={Add=function() end}}
            ISWorldObjectContextMenu={onActivateGenerator=function() end,onPlugGenerator=function() end,
                onInfoGenerator=function() end,addToolTip=function() return {} end}
        ''')
        self.lua.execute((ROOT/'client/ImmersiveSolarArrays/UI/ISAUI.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            generator:getModData().ApocBRISABackupOwner={x=0,y=0,z=0}
            local getup=function() end
            local toggle={onSelect=getup,param1=ISWorldObjectContextMenu.onActivateGenerator,param4=generator}
            local unplug={onSelect=getup,param1=ISWorldObjectContextMenu.onPlugGenerator,param3=generator}
            local normal={getModData=function() return {} end}
            local ordinary={onSelect=getup,param1=ISWorldObjectContextMenu.onActivateGenerator,param4=normal}
            local info={onSelect=ISWorldObjectContextMenu.onInfoGenerator,param1=generator}
            local submenu={onGetUpAndThen=getup,options={toggle,unplug,ordinary,info}}
            local root={onGetUpAndThen=getup,options={{subOption=1}},getSubMenu=function() return submenu end}
            ISA.UI.lockManagedGeneratorOptions(root)
            assert(toggle.notAvailable and unplug.notAvailable and toggle.toolTip.description=='IGUI_ISABackup_ControlHint')
            assert(not ordinary.notAvailable and not info.notAvailable)
        ''')

class BackupRuntimeTest(unittest.TestCase):
    def setUp(self):
        fixture=budget_fixture.PowerBudgetTest()
        fixture.setUp()
        self.lua,self.native=fixture.lua,fixture.native

    def test_runtime_reasons_and_thresholds(self):
        self.lua.execute('''
            history.samples={{hour=0,output=10}}
            local bank=makeBank(1,0)
            bank.charge=1; bank.conGenerator={}; bank.ISA_energyConfig={indoors=false}
            local b={fuel=5,condition=90,ison=true,failsafe=true}
            bank.ISA_backup=b
            Native.publishBackupStatus(bank,1)
            assert(bank.ISA_backupStatus.state=='running_charging' and bank.ISA_backupStatus.startPercent==2 and bank.ISA_backupStatus.stopPercent==4)
            assert(bank.ISA_backupStatus.fuelPercent==50 and bank.conGenerator.ison)
            history.samples[1].output=0
            Native.publishBackupStatus(bank,1); assert(bank.ISA_backupStatus.state=='running_waiting')
            b.ison=false
            Native.publishBackupStatus(bank,1); assert(bank.ISA_backupStatus.state=='standby')
            b.fuel=0
            Native.publishBackupStatus(bank,1); assert(bank.ISA_backupStatus.state=='no_fuel')
            b.fuel=5; b.condition=20
            Native.publishBackupStatus(bank,1); assert(bank.ISA_backupStatus.state=='low_condition')
            b.failsafe=false
            Native.publishBackupStatus(bank,1); assert(bank.ISA_backupStatus.state=='no_failsafe')
            bank.on=false
            Native.publishBackupStatus(bank,1); assert(bank.ISA_backupStatus.state=='bank_off')
        ''')

    def test_managed_generator_stops_when_bank_off_or_failsafe_missing(self):
        self.lua.execute('''
            local Model=require 'ImmersiveSolarArrays/PowerBank/EnergyModel'
            local bank=makeBank(1,0)
            bank.ISA_backup={managed=true,ison=true,fuel=5,condition=90,rate=1,failsafe=true}
            bank.on=false
            Model.step(bank,0,1,0,2)
            assert(not bank.ISA_backup.ison and bank.ISA_backup.fuel==5)
            bank.on=true; bank.ISA_backup.ison=true; bank.ISA_backup.failsafe=false
            Model.step(bank,1,2,0,2)
            assert(not bank.ISA_backup.ison and bank.ISA_backup.fuel==5)
        ''')

    def test_stale_hydro_flag_cannot_stop_automatic_backup_after_grid_shutoff(self):
        self.lua.execute('''
            function getWorld() return {isHydroPowerOn=function() return true end} end
            now=1
            history.samples={{hour=0,output=0,hydro=false}}
            local bank,g=makeBank(1,0)
            bank.charge=0; bank.conGenerator={x=2,y=0,z=0}
            bank.ISA_energyConfig={on=true,drain=2,npanels=1,maxcapacity=100,indoors=true,gridEligible=true}
            bank.ISA_backup={managed=true,ison=false,fuel=5,condition=90,rate=1,failsafe=true}
            Native.update(g,1)
            assert(bank.ISA_backup.ison and bank.ISA_backupStatus.state=='running_waiting')
        ''')

if __name__=='__main__': unittest.main()
