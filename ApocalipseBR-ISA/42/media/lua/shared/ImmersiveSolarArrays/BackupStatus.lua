local Status = {}
local keys = {
    running_charging="IGUI_ISABackup_RunningCharging", running_waiting="IGUI_ISABackup_RunningWaiting",
    standby="IGUI_ISABackup_Standby", no_failsafe="IGUI_ISABackup_NoFailsafe",
    bank_off="IGUI_ISABackup_BankOff", no_fuel="IGUI_ISABackup_NoFuel",
    low_condition="IGUI_ISABackup_LowCondition", grid="IGUI_ISABackup_Grid",
    pending="IGUI_ISABackup_Pending", none="IGUI_ISASummary_GenNoneConnected",
}

function Status.get(bank)
    if not bank.conGenerator then return keys.none,nil end
    local runtime=bank.ISA_backupStatus
    if runtime then return keys[runtime.state] or keys.pending,runtime end
    return keys.pending,nil
end

function Status.color(bank)
    if bank.conGenerator then return 0.2,0.85,0.35 end
    return 0.6,0.6,0.6
end

function Status.thresholdText(runtime)
    if not runtime then return getText("IGUI_ISABackup_Pending") end
    return getText("IGUI_ISABackup_Thresholds",string.format("%.1f",runtime.startPercent),string.format("%.1f",runtime.stopPercent))
end

function Status.fuelText(runtime)
    if not runtime then return getText("IGUI_ISABackup_Pending") end
    return getText("IGUI_ISABackup_FuelCondition",string.format("%.1f",runtime.fuelPercent),tostring(runtime.condition))
end

return Status
