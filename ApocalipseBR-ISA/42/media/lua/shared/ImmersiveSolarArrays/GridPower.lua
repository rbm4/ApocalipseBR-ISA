-- B42 grid policy. Generator coverage must never be used as evidence of mains.
local Grid = {}

function Grid.exists()
    return getSandboxOptions():doesPowerGridExist()
end

function Grid.cutoffHour()
    local options=getSandboxOptions()
    return (options:getElecShutModifier()-(options:getTimeSinceApo()-1)*30)*24
end

function Grid.eligible(square)
    return square~=nil and not square:isOutside() and not square:isNoPower()
end

function Grid.current(square)
    return square~=nil and not square:isOutside() and square:hasGridPower()
end

-- Both demand calculators exclude mains-powered appliances. Native generator
-- consumption also includes its 0.02 L/h idle floor (ISA converts at 800 Ah/L).
function Grid.coversLoad(drain, available)
    local idle=SandboxVars.ISA.DrainCalc==1 and 0 or 16
    return available==true and (drain or 0)<=idle+0.00001
end

return Grid
