"""Server activation and client request routing regressions with Lua 5.1."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1] / 'ApocalipseBR-ISA/42/media/lua'


class PowerBankActivationTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            function isClient() return false end
            SandboxVars = { ISA={} }
            Perks = { Electricity='Electricity' }
            roll=0
            function ZombRand() return roll end
            function getGameTime() return {getWorldAgeHours=function() return 10 end} end
            ISA = {nativePowerBanks=true, debugLog=function() end}
            ISA.delayedProcess = {new=function(self,object) return object end}
            package.loaded['ImmersiveSolarArrays/Utilities']=ISA
            package.loaded['Map/SGlobalObjectSystem']=true
            package.loaded['ImmersiveSolarArrays/PowerBank/PowerBankObject_Server']={}
            package.loaded['ImmersiveSolarArrays/PowerBank/NativeSimulation']={start=function() end}
            SGlobalObjectSystem={
                derive=function(self,name) return {} end,
                RegisterSystemClass=function() end
            }
            IsoUtils={DistanceToSquared=function(x1,y1,x2,y2) return (x1-x2)^2+(y1-y2)^2 end}
            character={x=0.5,y=1.5,z=0,level=3}
            function character:getX() return self.x end
            function character:getY() return self.y end
            function character:getZ() return self.z end
            function character:getPerkLevel() return self.level end
            function character:isTimedActionInstant() return true end
            square={getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
            generator={active=false}
            function generator:getSquare() return square end
            function generator:getObjectIndex() return 0 end
            function generator:isActivated() return self.active end
            function generator:requestSimulationUpdate() end
            function generator:update() bank.ISA_simulationHour=10 end
            bank={x=0,y=0,z=0,on=false,charge=1000,maxcapacity=1000,ISA_simulationHour=9}
            function bank:getIsoObject() return generator end
            function bank:updateDrain() end
            function bank:updateGenerator() generator.active=self.on and self.charge>0 end
            function bank:saveData() end
            package.loaded['TimedActions/ISBaseTimedAction']=true
            ISBaseTimedAction={}
            function ISBaseTimedAction:derive() local child={}; setmetatable(child,{__index=self}); return child end
            function ISBaseTimedAction.new(class,actor) return setmetatable({character=actor},{__index=class}) end
        """)
        self.lua.execute((ROOT / 'shared/ImmersiveSolarArrays/WorldUtilities.lua').read_text(encoding='utf-8'))
        shared = self.lua.execute((ROOT / 'shared/ImmersiveSolarArrays/PowerBankSystem_Shared.lua').read_text(encoding='utf-8'))
        self.lua.globals().package.loaded['ImmersiveSolarArrays/PowerBankSystem_Shared'] = shared
        system = self.lua.execute((ROOT / 'server/ImmersiveSolarArrays/PowerBank/PowerBankSystem_Server.lua').read_text(encoding='utf-8'))
        self.lua.globals().ISA.PBSystem_Server = system
        self.lua.globals().system = system
        self.lua.execute('function system:getLuaObjectAt() return bank end')
        self.lua.execute((ROOT / 'shared/ImmersiveSolarArrays/TimedActions/ActivatePowerbank.lua').read_text(encoding='utf-8'))

    def test_status_proximity_is_independent_of_electrical_skill(self):
        self.lua.execute("""
            character.level=0
            assert(ISA.WorldUtil.getValidBackupArea(character.level).distance==0)
            assert(ISA.WorldUtil.isWithinPowerBankRange(character,square))
            character.x=10
            assert(not ISA.WorldUtil.isWithinPowerBankRange(character,square))
            character.x=0.5; character.z=1
            assert(not ISA.WorldUtil.isWithinPowerBankRange(character,square))
        """)

    def test_server_action_switches_the_authoritative_generator(self):
        self.lua.execute("""
            local action=ISA_ActivatePowerBank:new(character,generator,true,0,0,0)
            assert(action:complete())
            assert(bank.on and generator.active and bank.ISA_simulationHour==10)
            action.activate=false
            assert(action:complete())
            assert(not bank.on and not generator.active)
        """)

    def test_native_activation_is_queued_without_running_inline_catchup(self):
        self.lua.execute('''
            local pending
            ISA.NativeSimulation={ensureCurrent=function() return false end,
                queueCommand=function(bank,name,player,args) pending={name=name,args=args} end}
            generator.update=function() error('Inline simulation is forbidden') end
            assert(system:setBankEnabled(character,bank,true))
            assert(not bank.on and pending.name=='activatePowerbank' and pending.args.activate)
            bank.ISA_simulationHour=10
            ISA.NativeSimulation.ensureCurrent=function() return true end
            assert(system:setBankEnabled(character,bank,true))
            assert(bank.on and generator.active)
        ''')

    def load_details_view(self):
        self.lua.execute("""
            package.loaded['ISUI/ISPanelJoypad']=true
            package.loaded['ImmersiveSolarArrays/UI/ISAUI']=true
            ISPanelJoypad=ISBaseTimedAction
            ISA.UI={rgbGood={r=0,g=1,b=0},rgbBad={r=1,g=0,b=0}}
            UIFont={Small=1,Medium=2}
            function getText(key) return key end
            function getTextManager() return {getFontHeight=function() return 12 end} end
            character.level=0
            bank.npanels=0; bank.drain=0; bank.luaSystem=system
            function bank:getSquare() return square end
            function bank:updateFromIsoObject() end
            function system:getMaxSolarOutput() return 0 end
        """)
        source = ROOT / 'client/ImmersiveSolarArrays/UI/ISAStatusWindowDetailsView.lua'
        self.lua.execute(source.read_text(encoding='utf-8'))

    def test_details_render_at_level_zero_and_report_actual_distance(self):
        self.load_details_view()
        self.lua.execute("""
            local view=setmetatable({width=400,parent={parent={luaPB=bank,playerObj=character}},
                devButton={setVisible=function() end},drawn={}}, {__index=ISA.StatusWindowDetailsView})
            function view:drawText(text) self.drawn[text]=true end
            view.drawTextRight=view.drawText
            function view:drawRect() end
            function view:drawRectBorder() end
            function view:setHeightAndParentHeight() end
            view:render()
            assert(view.drawn.ContextMenu_ISA_BatteryBank)
            assert(not view.drawn.IGUI_ISAWindow_Details_CantSee)
            character.x=10; view.drawn={}
            view:render()
            assert(view.drawn.IGUI_ISAWindow_Details_CantSee)
        """)

    def test_update_button_refreshes_local_devices_and_sends_refresh_request(self):
        self.load_details_view()
        self.lua.execute("""
            local refreshes,requests=0,0
            bank.on=true; generator.active=true
            function generator:setSurroundingElectricity() refreshes=refreshes+1 end
            function generator:getItemsPowered() return 'Fridge' end
            function system:sendCommand(player,command,args)
                assert(command=='refreshPowerbank' and player==character)
                assert(args.x==0 and args.y==0 and args.z==0 and args.activate==nil)
                requests=requests+1
            end
            local view=setmetatable({width=400,parent={parent={luaPB=bank,playerObj=character}},
                _cachedGenInfo=1}, {__index=ISA.StatusWindowDetailsView})
            view:updateDevices()
            assert(refreshes==1 and requests==1 and view._cachedGenInfo==nil)
            assert(bank.on and generator.active)
            function ISPanelJoypad.setVisible() end
            function view:setWidthAndParentWidth() end
            view:setVisible(true)
            assert(refreshes==2 and requests==1)
        """)

    def test_server_refresh_recalculates_devices_without_switching_and_is_throttled(self):
        self.lua.execute("""
            system.instance=system
            package.loaded['ImmersiveSolarArrays/PowerBank/PowerBankSystem_Server']=system
            nowMs=1000
            function getTimestampMs() return nowMs end
            refreshes=0; saved=0
            bank.on=true; generator.active=true
            function generator:setSurroundingElectricity() refreshes=refreshes+1 end
            function generator:getItemsPowered() return 'Fridge' end
            function bank:updateDrain() self.drain=42 end
            function bank:saveData() saved=saved+1 end
        """)
        source = ROOT / 'server/ImmersiveSolarArrays/PowerBank/PowerBankSystem_Commands.lua'
        self.lua.execute(source.read_text(encoding='utf-8'))
        self.lua.execute("""
            local args={x=0,y=0,z=0}
            assert(system.Commands.refreshPowerbank(character,args))
            assert(refreshes==1 and saved==1 and bank.drain==42 and bank.on and generator.active)
            assert(not system.Commands.refreshPowerbank(character,args))
            assert(refreshes==1)
            nowMs=2001
            assert(system.Commands.refreshPowerbank(character,args))
            assert(refreshes==2)
            character.x=10; nowMs=4000
            assert(not system.Commands.refreshPowerbank(character,args))
            assert(not system.Commands.refreshPowerbank(character,{x=0/0,y=0,z=0}))
            assert(not system.Commands.refreshPowerbank(character,{x=math.huge,y=0,z=0}))
            assert(not system.Commands.refreshPowerbank(character,{x=0.5,y=0,z=0}))
            assert(refreshes==2)
        """)

    def test_out_of_range_request_cannot_change_bank_state(self):
        self.lua.execute("""
            character.x=10
            assert(not system:setBankEnabled(character,bank,true))
            assert(not bank.on and not generator.active)
        """)

    def test_original_low_skill_start_failure_keeps_bank_off(self):
        self.lua.execute("""
            character.level=0; roll=1
            assert(not system:setBankEnabled(character,bank,true))
            assert(not bank.on and not generator.active)
        """)

    def test_switching_waits_for_pending_native_catchup(self):
        self.lua.execute("""
            function generator:update() bank.ISA_simulationHour=9.5 end
            assert(not system:setBankEnabled(character,bank,true))
            assert(not bank.on and not generator.active)
        """)

    def test_client_completion_uses_global_object_command_route(self):
        self.lua.execute("""
            function isClient() return true end
            local calls=0
            ISA.PBSystem_Client={sendCommand=function(self,player,command,args)
                assert(player==character and command=='activatePowerbank' and args.activate==true)
                calls=calls+1
            end}
            local action=ISA_ActivatePowerBank:new(character,generator,true,0,0,0)
            assert(action:complete())
            assert(calls==1 and not bank.on)
        """)


if __name__ == '__main__':
    unittest.main()
