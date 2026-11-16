if isClient() then return end
local ISA = require 'ImmersiveSolarArrays/Utilities'
local History = require 'ImmersiveSolarArrays/PowerBank/ProductionHistory'
local Model = require 'ImmersiveSolarArrays/PowerBank/EnergyModel'
local Grid = require 'ImmersiveSolarArrays/GridPower'
local Native = {MAX_STEPS=32, MAX_JOBS=8, MAX_FRAME_STEPS=256, FRAME_MS=2}
local started = false
local normal,backlog = {head=1,tail=0},{head=1,tail=0}
local queued,sequence = {},0
Native.metrics = {jobs=0,steps=0,failures=0,broadcasts=0,pending=0,historyGaps=0}
local function nowHour() return getGameTime():getWorldAgeHours() end
local function valid(o) return o and o:getSquare() and o:getObjectIndex()>=0 end
local function push(q,j) q.tail=q.tail+1; q[q.tail]=j end
local function pop(q)
    if q.head>q.tail then return end
    local j=q[q.head]; q[q.head]=nil; q.head=q.head+1
    if q.head>q.tail then q.head,q.tail=1,0 end
    return j
end
local function systemBank(generator)
    local s=ISA.PBSystem_Server
    if not s then return end
    local b=s:getLuaObjectOnSquare(generator:getSquare())
    if not b then s:loadIsoObject(generator); b=s:getLuaObjectOnSquare(generator:getSquare()) end
    return b
end
local function enqueue(bank,generator,backup)
    if queued[bank] then
        local j=queued[bank]
        if generator then j.generator=generator end
        if backup then j.backup=backup end
        return
    end
    local j={bank=bank,generator=generator,backup=backup,queuedMs=getTimestampMs()}
    bank._ISA_backlogSince=bank._ISA_backlogSince or j.queuedMs
    queued[bank]=j
    Native.metrics.pending=Native.metrics.pending+1
    local lag=nowHour()-(bank.ISA_simulationHour or nowHour())
    push(lag>24 and backlog or normal,j)
end
function Native.recordProduction()
    local s=ISA.PBSystem_Server
    if s then History.append(nowHour(),s:getModifiedSolarOutput(1),Grid.exists()) end
end
function Native.advance(bank,now,drain,allowance,deadline)
    local d=History.get()
    if d.last<d.first then Native.recordProduction(); d=History.get() end
    if d.last<d.first then return nil,0 end
    local start=math.min(bank.ISA_simulationHour or now,now)
    local oldest=d.samples[d.first].hour
    if start<oldest then
        bank.charge=0
        bank.ISA_historyLostUntil=oldest
        ISA.debugLog("History gap x=%s y=%s z=%s from=%.3f retainedFrom=%.3f; charge reset at retained boundary",
            tostring(bank.x),tostring(bank.y),tostring(bank.z),start,oldest)
        Native.metrics.historyGaps=Native.metrics.historyGaps+1
        if bank.ISA_backup then bank.ISA_backup.availableFrom=now end
        Model.transition(bank,start,false)
        start=math.min(oldest,now)
    end
    local index=History.at(start)
    local steps=0
    local cutoff=Grid.cutoffHour()
    while start<now and steps<(allowance or Native.MAX_STEPS) do
        if deadline and steps>0 and getTimestampMs()>=deadline then break end
        local nextSample=d.samples[index+1]
        local finish=nextSample and math.min(nextSample.hour,now) or now
        if cutoff>start then finish=math.min(finish,cutoff) end
        -- Also constrain old samples recorded from the stale global hydro flag.
        local grid=d.samples[index].hydro==true and start<cutoff
            and bank.ISA_energyConfig and bank.ISA_energyConfig.gridEligible==true
        start=Model.step(bank,start,finish,d.samples[index].output,drain,grid)
        steps=steps+1
        if nextSample and start>=nextSample.hour then index=index+1 end
    end
    bank.ISA_simulationHour=start
    return start,steps
end
local function observeBackup(bank,source)
    if not source then return end
    if not PowerBankBackup.claim(source,{x=bank.x,y=bank.y,z=bank.z}) then
        bank.conGenerator=false
        bank.ISA_backup=nil
        bank.ISA_backupStatus=nil
        return
    end
    if not source:isConnected() then
        bank.conGenerator=false
        bank.ISA_backup=nil
        PowerBankBackup.release(source)
        return
    end
    local fuel,condition,ison=source:getFuel(),source:getCondition(),source:isActivated()
    local state=bank.ISA_backup
    local rate=source:getTotalPowerUsing()*(SandboxVars.GeneratorFuelConsumption or 1)
    local item=ScriptManager.instance:getItem(source:getGeneratorItemType())
    local chance=item and item:getConditionLowerChance() or 30
    local failsafe=ISA.WorldUtil.findOnSquare(source:getSquare(),'solarmod_tileset_01_15') and true or false
    rate=math.max(0,rate)
    chance=math.max(1,chance)
    if not state then
        state={fuel=fuel,condition=condition,ison=ison,rate=rate,wearHours=0,wearChance=chance,availableFrom=nowHour(),failsafe=failsafe}
        bank.ISA_backup=state
        state.appliedFuel,state.appliedCondition,state.appliedOn=fuel,condition,ison
    elseif fuel~=state.observedFuel or condition~=state.observedCondition or ison~=state.observedOn
        or rate~=state.observedRate or failsafe~=state.observedFailsafe then
        local event={hour=nowHour(),rate=rate,wearChance=chance,failsafe=failsafe}
        if fuel~=(state.observedFuel or state.appliedFuel) then event.fuel=fuel end
        if condition~=(state.observedCondition or state.appliedCondition) then event.condition=condition end
        local previousOn=state.observedOn
        if previousOn==nil then previousOn=state.appliedOn end
        if ison~=previousOn then event.ison=ison end
        Model.observe(state,event)
    end
    state.observedFuel,state.observedCondition,state.observedOn=fuel,condition,ison
    state.observedRate,state.observedFailsafe=rate,failsafe
    state.managed=true
    return source
end
function Native.bindBackup(bank,source)
    return observeBackup(bank,source)
end
function Native.publishBackupStatus(bank,now)
    local b=bank.ISA_backup
    if not bank.conGenerator then bank.ISA_backupStatus=nil; return end
    if not b then bank.ISA_backupStatus=nil; return end
    local index,history=History.at(now)
    local production=history.samples[index] and history.samples[index].output*bank.npanels or 0
    local state="standby"
    if not bank.on then state="bank_off"
    elseif not b.failsafe then state="no_failsafe"
    elseif b.fuel<=0 then state="no_fuel"
    elseif b.condition<=20 and not b.ison then state="low_condition"
    elseif Grid.coversLoad(bank.drain,bank.ISA_energyConfig.gridEligible==true and Grid.exists()) then state="grid"
    elseif b.ison then state=production>0 and bank.charge<bank.maxcapacity and "running_charging" or "running_waiting" end
    local capacity=bank.maxcapacity
    local low=math.min(bank.drain,capacity*0.25)
    local high=math.min(bank.drain*2,capacity*0.75)
    bank.ISA_backupStatus={state=state,failsafe=b.failsafe or false,managed=true,
        fuelPercent=b.fuel*10,condition=b.condition,
        startPercent=capacity>0 and low/capacity*100 or 0,stopPercent=capacity>0 and high/capacity*100 or 0,
        hour=now}
    bank.conGenerator.ison=b.ison
end
function Native.update(generator,now,allowance,deadline,existingBank,source)
    local bank=existingBank or systemBank(generator)
    if not bank then return nil,0 end
    bank._ISA_processing=true
    if generator then generator:prepareSimulationUpdate() end
    if generator and bank._ISA_forceDevices then
        generator:setSurroundingElectricity()
        bank._ISA_forceDevices=nil
    end
    local cached=bank.ISA_energyConfig
    if not cached then
        bank:updateDrain()
        local square=generator and generator:getSquare()
        cached={on=bank.on,drain=bank.drain,npanels=bank.npanels,maxcapacity=bank.maxcapacity,
            indoors=square and square.isOutside and not square:isOutside() or false}
        bank.ISA_energyConfig=cached
    end
    if cached.indoors==nil and generator then cached.indoors=not generator:getSquare():isOutside() end
    local localGrid=generator and Grid.eligible(generator:getSquare())
    if cached.gridEligible==nil and generator then cached.gridEligible=localGrid end
    if not source then source=bank:getConGenerator() end
    if not bank.conGenerator then bank.ISA_backup=nil; source=nil
    elseif source and (bank.conGenerator.x~=source:getX() or bank.conGenerator.y~=source:getY() or bank.conGenerator.z~=source:getZ()) then
        source=bank:getConGenerator()
    end
    source=observeBackup(bank,source)
    local current={on=bank.on,drain=bank.drain,npanels=bank.npanels,maxcapacity=bank.maxcapacity}
    bank.on,bank.drain,bank.npanels,bank.maxcapacity=cached.on,cached.drain,cached.npanels,cached.maxcapacity
    local ok,processed,steps=pcall(Native.advance,bank,now,cached.on and cached.drain or 0,allowance,deadline)
    bank.on,bank.drain,bank.npanels,bank.maxcapacity=current.on,current.drain,current.npanels,current.maxcapacity
    if not ok then bank._ISA_processing=nil; error(processed) end
    if not processed then bank._ISA_processing=nil; return nil,steps end
    if processed==now then
        local finalizeStarted=getTimestampMs()
        Model.applyObservations(bank,now)
        local inventory=bank.ISA_pendingInventory
        if inventory then
            bank.maxcapacity=math.max(0,bank.maxcapacity+inventory.capacity)
            bank.charge=math.max(0,math.min(bank.maxcapacity,bank.charge+inventory.charge))
            bank.ISA_pendingInventory=nil
        end
        bank.charge=math.max(0,math.min(bank.maxcapacity,bank.charge))
        local controlGrid=cached.gridEligible==true
        if generator then controlGrid=localGrid end
        Model.control(bank,now,bank.drain,controlGrid and Grid.exists())
        local b=bank.ISA_backup
        if b then
            if source then
                source:applyISABackupState(b.fuel,math.floor(b.condition),b.ison)
                b.appliedFuel,b.appliedCondition,b.appliedOn=source:getFuel(),source:getCondition(),source:isActivated()
                b.observedFuel,b.observedCondition,b.observedOn=b.appliedFuel,b.appliedCondition,b.appliedOn
                if bank.conGenerator then bank.conGenerator.ison=b.appliedOn end
            end
        end
        if generator then
            bank:updateDrain()
            bank:updateBatteries(generator:getContainer(),bank.maxcapacity>0 and bank.charge/bank.maxcapacity or 0)
            bank:updateGenerator()
            bank:updateSprite()
        end
        bank.ISA_energyConfig={on=bank.on,drain=bank.drain,npanels=bank.npanels,maxcapacity=bank.maxcapacity,
            indoors=cached.indoors,gridEligible=cached.gridEligible}
        if generator then bank.ISA_energyConfig.gridEligible=localGrid end
        Native.publishBackupStatus(bank,now)
        local mains=bank.ISA_energyConfig.gridEligible==true and Grid.exists()
        local mainsCoversLoad=Grid.coversLoad(bank.drain,mains)
        Model.transition(bank,now,mainsCoversLoad
            or (b and b.ison and b.fuel>0 and b.condition>0) or (bank.on and bank.charge>0) or false)
        bank:saveData(true)
        Native.metrics.broadcasts=Native.metrics.broadcasts+1
        Native.metrics.maxFinalizeMs=math.max(Native.metrics.maxFinalizeMs or 0,getTimestampMs()-finalizeStarted)
        Native.metrics.maxCatchupMs=math.max(Native.metrics.maxCatchupMs or 0,getTimestampMs()-(bank._ISA_backlogSince or finalizeStarted))
        bank._ISA_backlogSince=nil
        ISA.debugLog("Power bank settled x=%s y=%s z=%s hour=%.3f charge=%.3f capacity=%.3f backupFuel=%.3f supply=%s on=%s grid=%s gridEligible=%s drain=%.3f backupOn=%s simOn=%s simDrain=%.3f gridCoversLoad=%s",
            tostring(bank.x),tostring(bank.y),tostring(bank.z),now,bank.charge,bank.maxcapacity,
            b and b.fuel or 0,tostring(bank.ISA_supply.powered),tostring(bank.on),tostring(mains),
            tostring(bank.ISA_energyConfig.gridEligible),bank.drain,tostring(b and b.ison or false),tostring(cached.on),cached.drain,tostring(mainsCoversLoad))
    else bank:saveData(false) end
    if generator then
        if processed==now then generator:completeUpdate(processed,SandboxVars.ISA.ChargeFreq==1 and 1/6 or 1)
        else generator:checkpointUpdate(processed) end
    end
    bank._ISA_processing=nil
    if processed==now and bank._ISA_command then
        local command=bank._ISA_command
        bank._ISA_command=nil
        local handler=ISA.PBSystem_Server.Commands[command.name]
        if handler then handler(command.player,command.args) end
    end
    return processed,steps
end

function Native.inventoryDelta(bank,charge,capacity)
    local delta=bank.ISA_pendingInventory or {charge=0,capacity=0}
    bank.ISA_pendingInventory=delta
    delta.charge=delta.charge+charge
    delta.capacity=delta.capacity+capacity
    enqueue(bank,bank:getIsoObject())
    bank:saveData(false)
end
function Native.request(generator)
    local bank=systemBank(generator)
    if not bank then return end
    enqueue(bank,generator)
    generator:deferUpdate()
end
function Native.requestBackup(source,owner)
    local s=ISA.PBSystem_Server
    if not s then return end
    if not owner or type(owner.x)~='number' or type(owner.y)~='number' or type(owner.z)~='number' then
        PowerBankBackup.release(source)
        return
    end
    local bank=s and owner and s:getLuaObjectAt(owner.x,owner.y,owner.z)
    local link=bank and bank.conGenerator
    if not link or link.x~=source:getX() or link.y~=source:getY() or link.z~=source:getZ() then
        PowerBankBackup.release(source)
        return
    end
    enqueue(bank,bank:getIsoObject(),source)
end
function Native.ensureCurrent(bank)
    if bank.ISA_simulationHour and bank.ISA_simulationHour>=nowHour() then return true end
    enqueue(bank,bank:getIsoObject())
    return false
end
function Native.queueCommand(bank,name,player,args)
    -- One pending intent per bank, latest request wins. Revalidated on execution.
    bank._ISA_command={name=name,player=player,args=args}
    enqueue(bank,bank:getIsoObject())
end
function Native.processQueue()
    History.prune()
    local deadline=getTimestampMs()+Native.FRAME_MS
    local jobs,steps,available=0,0,Native.metrics.pending
    while jobs<math.min(available,Native.MAX_JOBS) and steps<Native.MAX_FRAME_STEPS and getTimestampMs()<deadline do
        sequence=sequence+1
        local preferred=sequence%3==0 and backlog or normal
        local j=pop(preferred) or pop(preferred==normal and backlog or normal)
        if not j then break end
        local bank=j.bank
        queued[bank]=nil; Native.metrics.pending=Native.metrics.pending-1
        local generator=valid(j.generator) and bank:getIsoObject()==j.generator and j.generator or nil
        local source=valid(j.backup) and j.backup or nil
        Native.metrics.maxQueueAgeMs=math.max(Native.metrics.maxQueueAgeMs or 0,getTimestampMs()-j.queuedMs)
        if (generator or source) and ISA.PBSystem_Server:getLuaObjectAt(bank.x,bank.y,bank.z)==bank then
            local target=nowHour()
            local ok,processed,used=pcall(Native.update,generator,target,math.min(Native.MAX_STEPS,Native.MAX_FRAME_STEPS-steps),deadline,bank,source)
            if ok then
                steps=steps+(used or 0)
                if processed and processed<target then enqueue(bank,generator,source) end
                if not processed and generator then generator:failScheduledUpdate() end
            else
                bank._ISA_processing=nil
                Native.metrics.failures=Native.metrics.failures+1
                if generator then generator:failScheduledUpdate() end
                if source then PowerBankBackup.stop(source) end
                print('[ISA] Budgeted power update failed: '..tostring(processed))
            end
        else
            bank._ISA_command=nil
            bank._ISA_backlogSince=nil
            if j.generator then j.generator:failScheduledUpdate() end
        end
        jobs=jobs+1
    end
    Native.metrics.jobs=Native.metrics.jobs+jobs
    Native.metrics.steps=Native.metrics.steps+steps
    Native.metrics.lastFrameMs=Native.FRAME_MS-(deadline-getTimestampMs())
    Native.metrics.maxFrameMs=math.max(Native.metrics.maxFrameMs or 0,Native.metrics.lastFrameMs)
    if jobs>0 then ISA.debugLog('Power scheduler jobs=%d steps=%d pending=%d elapsedMs=%d',jobs,steps,Native.metrics.pending,Native.metrics.lastFrameMs) end
end
function Native.start()
    if started then return end
    started=true
    ISA.NativeSimulation=Native
    Hook.OnPowerBankUpdate.Add(Native.request)
    Hook.OnPowerBankBackupUpdate.Add(Native.requestBackup)
    Events.OnTick.Add(Native.processQueue)
    Events.EveryTenMinutes.Add(Native.recordProduction)
    Events.OnSGlobalObjectSystemInit.Add(Native.recordProduction)
    PowerBankBackup.enable()
    ISA.debugLog('Subscribed budgeted power-bank scheduler and backup ownership')
end
return Native
