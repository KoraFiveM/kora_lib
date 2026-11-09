local DEFAULT_MODE = "weighted"
local MAX_REWARD_RESULTS = 10000

---Resolves an item's `amount` field into a concrete number.
---@param item QBRewardItem
---@return number
local function resolveAmount(item)
    local amount = item.amount

    if amount == nil then
        return 1
    end

    if Kora.util.isFiniteNumber(amount) then
        return amount
    end

    assert(type(amount) == "table" and Kora.util.isInteger(amount.min) and Kora.util.isInteger(amount.max),
        "item.amount must be a number or a { min, max } table with integer bounds")
    assert(amount.min <= amount.max, "item.amount.min must not be greater than item.amount.max")

    return math.random(amount.min, amount.max)
end

---Copies `item` into a reward entry: every field except `chance`, plus a resolved `amount`.
---@param item QBRewardItem
---@return table
local function toReward(item)
    local reward = {}

    for key, value in pairs(item) do
        if key ~= "chance" then
            reward[key] = value
        end
    end

    reward.amount = resolveAmount(item)

    return reward
end

---Fills in an equal share of `chance` for items that omit it: weight `1` (weighted) or an equal split of `100` (percent).
---@param items QBRewardItem[]
---@param mode "weighted" | "percent"
---@return number[] chances Same length/order as `items`.
local function resolveChances(items, mode)
    local chances = {}
    local unspecified = 0

    for i = 1, #items do
        local item = items[i]
        if item.chance ~= nil then
            assert(Kora.util.isFiniteNumber(item.chance) and item.chance > 0, "item.chance must be a positive number")
            if mode == "percent" then
                assert(item.chance <= 100, "item.chance must not exceed 100 in percent mode")
            end
            chances[i] = item.chance
        else
            unspecified = unspecified + 1
        end
    end

    if unspecified > 0 then
        local defaultChance = mode == "percent" and (100 / unspecified) or 1
        for i = 1, #items do
            local item = items[i]
            if item.chance == nil then
                chances[i] = defaultChance
            end
        end
    end

    return chances
end

---Builds the `{value, weight}` pairs `Kora.util.weightedChoice` expects.
---@param items QBRewardItem[]
---@param chances number[]
---@return {[1]: QBRewardItem, [2]: number}[]
local function toWeightedPairs(items, chances)
    local pairs_ = {}
    for i = 1, #items do
        pairs_[i] = { items[i], chances[i] }
    end
    return pairs_
end

---Runs one roll: one item in weighted mode, or every item independently in percent mode (any number, including none).
---@param items QBRewardItem[]
---@param chances number[]
---@param weightedPairs {[1]: QBRewardItem, [2]: number}[]
---@param mode "weighted" | "percent"
---@return QBRewardItem[]
local function roll(items, chances, weightedPairs, mode)
    if mode == "weighted" then
        return { Kora.util.weightedChoice(weightedPairs) }
    end

    local hits = {}
    for i = 1, #items do
        if math.random() * 100 <= chances[i] then
            hits[#hits + 1] = items[i]
        end
    end

    return hits
end

---Generates rewards from a pool of possible items; `"weighted"` (default) picks one item per roll, `"percent"` rolls each independently.
---@param items QBRewardItem[] Reward pool. Must be non-empty.
---@param opts? { mode?: "weighted" | "percent", rolls?: integer, allowNone?: boolean }
---@return table[] rewards Copies of the winning items, each with `amount` resolved to a number. Guaranteed non-empty unless `opts.allowNone` is `true`.
function Kora.rewards.generate(items, opts)
    assert(type(items) == "table", "items must be a non-empty array")
    local itemCount = 0
    for index, item in pairs(items) do
        assert(Kora.util.isInteger(index) and index >= 1 and type(item) == 'table',
            'items must be a dense array of tables')
        itemCount = itemCount + 1
    end
    assert(itemCount > 0 and itemCount == #items, 'items must be a non-empty dense array')
    assert(opts == nil or type(opts) == "table", "opts must be a table")

    opts = opts or {}

    local mode = opts.mode == nil and DEFAULT_MODE or opts.mode
    assert(mode == "weighted" or mode == "percent", "opts.mode must be \"weighted\" or \"percent\"")

    local rolls = opts.rolls == nil and 1 or opts.rolls
    assert(Kora.util.isInteger(rolls) and rolls >= 1 and rolls <= MAX_REWARD_RESULTS,
        ("opts.rolls must be an integer between 1 and %d"):format(MAX_REWARD_RESULTS))
    assert(opts.allowNone == nil or type(opts.allowNone) == "boolean", "opts.allowNone must be a boolean")
    assert(mode ~= 'percent' or itemCount * rolls <= MAX_REWARD_RESULTS,
        ("percent reward generation cannot exceed %d potential results"):format(MAX_REWARD_RESULTS))

    local chances = resolveChances(items, mode)
    local weightedPairs = toWeightedPairs(items, chances)

    local rewards = {}
    for _ = 1, rolls do
        local rolledItems = roll(items, chances, weightedPairs, mode)
        for itemIndex = 1, #rolledItems do
            rewards[#rewards + 1] = toReward(rolledItems[itemIndex])
        end
    end

    if #rewards == 0 and not opts.allowNone then
        rewards[1] = toReward(Kora.util.weightedChoice(weightedPairs))
    end

    return rewards
end
