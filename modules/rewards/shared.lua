---@class QBRewardItem : table
---@field chance? number Weighted mode: a relative weight (> 0). Percent mode: a 0-100 probability. Items that omit this share an equal chance with every other item that also omits it.
---@field amount? number | { min: number, max: number } Flat amount, or a `{ min, max }` range to roll. Defaults to `1`. Any other fields (name, label, ...) are passed through untouched.

local DEFAULT_MODE = "weighted"

---Resolves an item's `amount` field into a concrete number.
---@param item QBRewardItem
---@return number
local function resolveAmount(item)
    local amount = item.amount

    if amount == nil then
        return 1
    end

    if type(amount) == "number" then
        return amount
    end

    assert(type(amount) == "table" and type(amount.min) == "number" and type(amount.max) == "number",
        "item.amount must be a number or a { min, max } table")
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

---Fills in an equal share of `chance` for every item that didn't specify one:
---a weight of `1` each in weighted mode, or an equal split of `100` in percent mode.
---@param items QBRewardItem[]
---@param mode "weighted" | "percent"
---@return number[] chances Same length/order as `items`.
local function resolveChances(items, mode)
    local chances = {}
    local unspecified = 0

    for i = 1, #items do
        local item = items[i]
        if item.chance ~= nil then
            assert(type(item.chance) == "number" and item.chance > 0, "item.chance must be a positive number")
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

---Builds the `{value, weight}` pairs `QB.util.weightedChoice` expects.
---@param items QBRewardItem[]
---@param chances number[]
---@return {[1]: QBRewardItem, [2]: number}[]
local function toWeightedPairs(items, chances)
    local pairs_ = {}
    for i = 1, #items do
        local item = items[i]
        pairs_[i] = { item, chances[i] }
    end
    return pairs_
end

---Runs one roll. Weighted mode picks exactly one item. Percent mode rolls
---every item independently against its own chance, so a single roll can
---return any number of items, including all of them or none.
---@param items QBRewardItem[]
---@param chances number[]
---@param weightedPairs {[1]: QBRewardItem, [2]: number}[]
---@param mode "weighted" | "percent"
---@return QBRewardItem[]
local function roll(items, chances, weightedPairs, mode)
    if mode == "weighted" then
        return { QB.util.weightedChoice(weightedPairs) }
    end

    local hits = {}
    for i = 1, #items do
        local item = items[i]
        if math.random() * 100 <= chances[i] then
            hits[#hits + 1] = item
        end
    end

    return hits
end

---Generates rewards from a pool of possible items.
---
---In `"weighted"` mode (the default) each roll picks exactly one item, with
---`chance` acting as a relative weight against the others. In `"percent"`
---mode every item is rolled independently against its own `chance` as a
---0-100 probability, so a single roll can yield any number of items,
---including all of them or none.
---@param items QBRewardItem[] Reward pool. Must be non-empty.
---@param opts? { mode?: "weighted" | "percent", rolls?: integer, allowNone?: boolean }
---@return table[] rewards Copies of the winning items, each with `amount` resolved to a number. Guaranteed non-empty unless `opts.allowNone` is `true`.
function QB.rewards.generate(items, opts)
    assert(type(items) == "table" and #items > 0, "items must be a non-empty array")

    opts = opts or {}

    local mode = opts.mode or DEFAULT_MODE
    assert(mode == "weighted" or mode == "percent", "opts.mode must be \"weighted\" or \"percent\"")

    local rolls = opts.rolls or 1
    assert(type(rolls) == "number" and rolls >= 1 and rolls % 1 == 0, "opts.rolls must be a positive integer")

    local chances = resolveChances(items, mode)
    local weightedPairs = toWeightedPairs(items, chances)

    local rewards = {}
    for _ = 1, rolls do
        local rolledItems = roll(items, chances, weightedPairs, mode)
        for itemIndex = 1, #rolledItems do
            local item = rolledItems[itemIndex]
            rewards[#rewards + 1] = toReward(item)
        end
    end

    -- Percent mode (and, in principle, a mis-tuned weighted table) can come
    -- up empty. Unless the caller explicitly allows that, force one more
    -- pick so a reward roll never hands back nothing.
    if #rewards == 0 and not opts.allowNone then
        rewards[1] = toReward(QB.util.weightedChoice(weightedPairs))
    end

    return rewards
end
