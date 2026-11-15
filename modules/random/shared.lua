local MAX_PICK_COUNT = 10000

---Picks one or more random values from an array. Multiple picks are made with
---replacement and may therefore contain the same value more than once.
---@generic T
---@param list T[]
---@param options? KoraRandomPickOptions
---@return T|T[] value
function Kora.random.pick(list, options)
    assert(type(list) == 'table', KoraLang('Modules.Random.validation_kora_random_pick_requires_a_non_empty_array'))
    local listCount = 0
    for index in pairs(list) do
        assert(Kora.util.isInteger(index) and index >= 1, KoraLang('Modules.Random.validation_kora_random_pick_requires_a_dense_array'))
        listCount = listCount + 1
    end
    assert(listCount > 0 and listCount == #list, KoraLang('Modules.Random.validation_kora_random_pick_requires_a_non_empty_dense'))
    assert(options == nil or type(options) == 'table', KoraLang('Modules.Random.validation_kora_random_pick_options_must_be_a_table'))

    options = options or {}
    local count = options.count == nil and 1 or options.count
    local maxIndex = options.maxIndex == nil and #list or options.maxIndex

    assert(Kora.util.isInteger(count) and count >= 1 and count <= MAX_PICK_COUNT,
        ('Kora.random.pick count must be an integer between 1 and %d.'):format(MAX_PICK_COUNT))
    assert(Kora.util.isInteger(maxIndex) and maxIndex >= 1 and maxIndex <= #list,
        'Kora.random.pick maxIndex must be an integer between 1 and the array length.')

    if count == 1 then
        return list[math.random(1, maxIndex)]
    end

    local values = {}
    for index = 1, count do
        values[index] = list[math.random(1, maxIndex)]
    end

    return values
end
