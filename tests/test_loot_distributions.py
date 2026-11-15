"""Lua 5.1 integration checks against the installed vanilla distribution tables.

Run: py -m unittest discover -s tests -v
Requires lupa (Lua 5.1 backend) and the local Project Zomboid install.
"""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
VANILLA = Path(r"Z:\SteamLibrary\steamapps\common\ProjectZomboid\media\lua\server")
SOURCE = ROOT / "ApocalipseBR-ISA/42/media/lua/server/ImmersiveSolarArrays/Items/Distributions.lua"


class LootDistributionsTest(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            ISA = {}
            messages = {}
            print = function(message) messages[#messages + 1] = message end
            SandboxVars = { ISA = {} }
            parseCount = 0
            ItemPickerJava = { Parse = function() parseCount = parseCount + 1 end }
            function copyTable(source)
                local result = {}
                for key, value in pairs(source) do
                    result[key] = type(value) == "table" and copyTable(value) or value
                end
                return result
            end
            Events = { OnPostDistributionMerge = {}, OnLoadedMapZones = {} }
            for _, event in pairs(Events) do
                event.handlers = {}
                event.Add = function(callback) event.handlers[#event.handlers + 1] = callback end
            end
            package.loaded["ImmersiveSolarArrays/Utilities"] = ISA
        """)
        for path in sorted(VANILLA.glob("Items/Distribution_*.lua")) + sorted(VANILLA.glob("Vehicles/VehicleDistribution_*.lua")):
            self.lua.execute(path.read_text(encoding="utf-8-sig"))
        for module in ("Items/Distributions", "Items/ProceduralDistributions", "Vehicles/VehicleDistributions"):
            self.lua.execute((VANILLA / (module + ".lua")).read_text(encoding="utf-8-sig"))
            self.lua.globals().package.loaded[module] = True
        self.loot = self.lua.execute(SOURCE.read_text(encoding="utf-8"))

    def weights(self, distribution, item):
        items = distribution["items"]
        return [items[i + 1] for i in range(1, len(items), 2) if items[i] == item]

    def test_registers_once_and_preserves_vanilla_generators(self):
        pd = self.lua.globals().ProceduralDistributions.list
        native = list(pd.CrateGenerator.junk["items"].values())
        self.assertEqual(self.weights(pd.CrateElectronics, "ISA.SolarPanel"), [])
        self.loot.register()
        self.loot.register()
        self.assertEqual(self.weights(pd.CrateElectronics, "ISA.SolarPanel"), [0.10])
        self.assertEqual(self.weights(pd.CrateGenerator.junk, "ISA.PowerBank"), [2.0])
        self.assertEqual(list(pd.CrateGenerator.junk["items"].values())[:len(native)], native)
        self.assertEqual(len(self.lua.globals().messages), 0, list(self.lua.globals().messages.values()))

    def test_late_sandbox_options_zero_and_reapply(self):
        self.loot.register()
        options = self.lua.globals().SandboxVars.ISA
        options.LRMSolarPanels = 0
        options.LRMBatteries = 0
        options.LRMMisc = 0
        options.BatteryBankSpawn = 1
        self.loot.applySandboxWeights()
        pd = self.lua.globals().ProceduralDistributions.list
        self.assertEqual(self.weights(pd.CrateElectronics, "ISA.SolarPanel"), [0])
        self.assertEqual(self.weights(pd.CrateGenerator.junk, "ISA.PowerBank"), [0])
        self.assertEqual(self.weights(pd.ISASolarBox, "ISA.DeepCycleBattery"), [0])
        options.LRMSolarPanels = 2
        options.BatteryBankSpawn = 4
        self.loot.applySandboxWeights()
        self.loot.applySandboxWeights()
        self.assertEqual(self.weights(pd.CrateElectronics, "ISA.SolarPanel"), [0.20])
        self.assertEqual(self.weights(pd.CrateGenerator.junk, "ISA.PowerBank"), [6.0])
        self.assertEqual(self.weights(pd.ISASolarBox, "ISA.SolarPanel"), [96])

    def test_vehicle_stash_and_missing_optional_target(self):
        self.lua.globals().ProceduralDistributions.list.BookstoreMisc = None
        self.loot.register()
        self.loot.applySandboxWeights()
        self.assertEqual(len(self.lua.globals().messages), 1)
        vehicle = self.lua.globals().VehicleDistributions.ElectricianTruckBed
        self.assertEqual(self.weights(vehicle, "ISA.PowerBank"), [0.10])
        self.assertEqual(self.weights(vehicle, "ISA.DeepCycleBattery"), [1.0])
        stash = self.lua.globals().SuburbsDistributions.ISASolarBoxCache.SolarBox
        self.assertEqual(stash.rolls, 32)
        self.assertEqual(self.weights(stash, "ISA.SolarPanel"), [48])
        self.loot.insertItemsToMultipleLists(
            self.lua.globals().SuburbsDistributions.all,
            self.lua.table_from(["inventorymale", "missing"]),
            self.lua.table_from(["ISA.Stash_RiversideW1", 0.1]),
        )

    def test_only_startup_callbacks_registered(self):
        events = self.lua.globals().Events
        self.assertEqual(len(events.OnPostDistributionMerge.handlers), 1)
        self.assertEqual(len(events.OnLoadedMapZones.handlers), 1)
        events.OnPostDistributionMerge.handlers[1]()
        self.lua.globals().ItemPickerJava.doParse = True
        events.OnLoadedMapZones.handlers[1]()
        self.assertEqual(self.lua.globals().parseCount, 1)
        self.assertIsNone(self.lua.globals().ItemPickerJava.doParse)

    def test_changed_lua_syntax(self):
        compile_lua = self.lua.eval("function(text, name) local fn, err = loadstring(text, name); assert(fn, err) end")
        for path in (SOURCE, SOURCE.parents[1] / "World/MapObjects.lua"):
            compile_lua(path.read_text(encoding="utf-8"), str(path))


if __name__ == "__main__":
    unittest.main()
