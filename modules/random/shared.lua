---@class QBRandomPickOptions
---@field count? integer Number of independent picks. Defaults to 1.
---@field maxIndex? integer Highest array index eligible for selection. Defaults to `#list`.

---Picks one or more random values from an array. Multiple picks are made with
---replacement and may therefore contain the same value more than once.
---@generic T
---@param list T[]
---@param options? QBRandomPickOptions
---@return T|T[] value
function QB.random.pick(list, options)
    assert(type(list) == 'table' and #list > 0, 'QB.random.pick requires a non-empty array.')
    assert(options == nil or type(options) == 'table', 'QB.random.pick options must be a table.')

    options = options or {}
    local count = options.count or 1
    local maxIndex = options.maxIndex or #list

    assert(type(count) == 'number' and count >= 1 and count % 1 == 0,
        'QB.random.pick count must be a positive integer.')
    assert(type(maxIndex) == 'number' and maxIndex >= 1 and maxIndex % 1 == 0 and maxIndex <= #list,
        'QB.random.pick maxIndex must be an integer between 1 and the array length.')

    if count == 1 then
        return list[math.random(1, maxIndex)]
    end

    local values = {}
    for index = 1, count do
        values[index] = list[math.random(1, maxIndex)]
    end

    return values
end
