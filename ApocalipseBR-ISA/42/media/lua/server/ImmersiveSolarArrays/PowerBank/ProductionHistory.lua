if isClient() then return end
local History = { LIMIT = 4096 }
local function data()
    local d = ModData.getOrCreate("ApocBRISA_Production")
    d.samples = d.samples or {}
    if not d.last then
        d.last = #d.samples
        d.first = math.max(1, d.last - History.LIMIT + 1)
        d.purge = 1
    end
    return d
end

function History.get() return data() end

function History.prune()
    local d = data()
    local cursor = d.purge or d.first
    local finish = math.min(d.first - 1, cursor + 127)
    for i = cursor, finish do d.samples[i] = nil end
    d.purge = finish + 1
end

function History.append(hour, output, hydro)
    local d = data()
    local previous = d.samples[d.last]
    if previous and previous.hour >= hour then return end
    -- Identical adjacent rates are an exact piecewise-constant compaction.
    if previous and previous.output == output and previous.hydro == hydro then return end
    d.last = d.last + 1
    d.samples[d.last] = {hour = hour, output = output, hydro = hydro}
    local first = math.max(1, d.last - History.LIMIT + 1)
    if first > d.first then
        -- One normal eviction; legacy migration is drained separately in batches.
        d.samples[d.first] = nil
        d.first = first
    end
end

function History.at(hour)
    local d = data()
    local low, high = d.first, d.last
    while low <= high do
        local mid = math.floor((low + high) / 2)
        if d.samples[mid].hour <= hour then low = mid + 1 else high = mid - 1 end
    end
    return math.max(d.first, high), d
end

return History
