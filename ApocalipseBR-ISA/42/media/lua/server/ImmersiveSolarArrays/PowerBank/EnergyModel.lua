if isClient() then return end
local Model = {}
local EPS = 1e-8
function Model.observe(state, event)
    local q=state.events or {first=1,last=0}
    state.events=q
    if q.last-q.first+1>=64 then
        state.observationGapUntil=event.hour
        for i=q.first,q.last do q[i]=nil end
        q.first,q.last=1,0
    end
    q.last=q.last+1
    q[q.last]=event
end

function Model.applyObservations(bank, hour)
    local b=bank.ISA_backup
    local q=b and b.events
    while q and q.first<=q.last and q[q.first].hour<=hour do
        local event=q[q.first]
        if event.fuel~=nil then b.fuel=event.fuel end
        if event.condition~=nil then b.condition=event.condition end
        if event.ison~=nil then b.ison=event.ison end
        b.rate,b.wearChance,b.failsafe=event.rate,event.wearChance,event.failsafe
        q[q.first]=nil
        q.first=q.first+1
    end
end
local function supply(bank, backup, production, hour, grid)
    return grid or (backup and hour >= (backup.availableFrom or 0) and backup.ison and backup.fuel > EPS and backup.condition > 0)
        or (bank.on and (bank.charge > EPS or production > bank.drain)) or false
end

function Model.transition(bank, hour, powered)
    local h = bank.ISA_supply or { first=1, last=0 }
    bank.ISA_supply = h
    if h.powered == powered then return end
    h.powered = powered
    h.last = h.last + 1
    h[h.last] = {hour=hour, powered=powered}
    if h.last - h.first >= 256 then
        h[h.first] = nil
        h.first = h.first + 1
    end
end

-- One bounded state-machine step. No world calls, physical toggles or item loops.
function Model.step(bank, start, finish, output, drain, grid)
    local b = bank.ISA_backup
    Model.applyObservations(bank,start)
    local events=b and b.events
    if events and events.first<=events.last then finish=math.min(finish,events[events.first].hour) end
    local production = math.max(0, output * bank.npanels)
    local demand = bank.on and not grid and drain or 0
    local available = b and start >= (b.availableFrom or 0)
    if available then
        if b.fuel <= EPS or b.condition <= 0 then b.ison = false end
        if b.failsafe and bank.on and grid then b.ison=false end
        if b.failsafe and bank.on and b.fuel > EPS and b.condition > 0 and demand > 0 then
            -- Hysteresis prevents infinite switching at one charge threshold.
            local low = math.min(demand, bank.maxcapacity * 0.25)
            local high = math.min(demand * 2, bank.maxcapacity * 0.75)
            if not b.ison and b.condition > 20 and bank.charge <= low + EPS then b.ison = true
            elseif b.ison and bank.maxcapacity > EPS and bank.charge >= high - EPS then b.ison = false end
        end
    end
    local running = available and b.ison
    local rate = production - (running and 0 or demand)
    local stop = finish
    if b and not available then stop=math.min(stop,b.availableFrom) end
    local function boundary(hours)
        if hours > EPS then stop = math.min(stop, start + hours) end
    end
    if rate < -EPS and bank.charge > EPS then boundary(bank.charge / -rate) end
    if rate > EPS and bank.charge < bank.maxcapacity - EPS then boundary((bank.maxcapacity-bank.charge)/rate) end
    if available and b.failsafe and bank.on and demand > 0 then
        local threshold = running and math.min(demand*2,bank.maxcapacity*0.75) or math.min(demand,bank.maxcapacity*0.25)
        if running and rate > EPS then boundary((threshold-bank.charge)/rate)
        elseif not running and rate < -EPS then boundary((bank.charge-threshold)/-rate) end
    end
    if running then
        if b.rate > EPS then boundary(b.fuel/b.rate) end
        boundary(1-(b.wearHours or 0))
    end
    Model.transition(bank, start, supply(bank,b,production,start,grid))
    local elapsed = stop-start
    bank.charge = math.max(0,math.min(bank.maxcapacity,bank.charge+rate*elapsed))
    if running then
        b.fuel = math.max(0,b.fuel-b.rate*elapsed)
        b.wearHours = (b.wearHours or 0)+elapsed
        if b.wearHours >= 1-EPS then
            b.wearHours = 0
            if ZombRand(b.wearChance or 30) == 0 then b.condition = math.max(0,b.condition-ZombRand(1,3)) end
        end
        if b.fuel <= EPS or b.condition <= 0 then b.ison = false end
    end
    Model.transition(bank, stop, supply(bank,b,production,stop,grid))
    return stop
end

return Model
