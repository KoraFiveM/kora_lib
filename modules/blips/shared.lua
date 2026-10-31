-- The named pause-map categories are deliberately fixed. GTA only reserves a
-- small numeric range for script-defined legend groups, so allocating ids in
-- creation order makes the same category move between ids after resource
-- restarts. Keeping the catalogue in shared code gives every realm and every
-- client the same name -> native id contract.
local DEFINITIONS = {
    { key = 'Other', name = 'Other', label = 'Other', id = 12 },
    { key = 'Bank', name = 'Bank', label = 'Bank', id = 13 },
    { key = 'Bar', name = 'Bar', label = 'Bar', id = 14 },
    { key = 'Business', name = 'Business', label = 'Business', id = 15 },
    { key = 'Clothing', name = 'Clothing', label = 'Clothing', id = 16 },
    { key = 'Convenience', name = 'Convenience', label = 'Convenience', id = 17 },
    { key = 'Dispatch', name = 'Dispatch', label = 'Dispatch', id = 18 },
    { key = 'Evidence', name = 'Evidence', label = 'Evidence', id = 19 },
    { key = 'Fuel', name = 'Fuel', label = 'Fuel', id = 20 },
    { key = 'Garage', name = 'Garage', label = 'Garage', id = 21 },
    { key = 'Gang Garage', name = 'Gang Garage', label = 'Gang Garage', id = 22 },
    { key = 'Grooming', name = 'Grooming', label = 'Grooming', id = 23 },
    { key = 'Hospital', name = 'Hospital', label = 'Hospital', id = 24 },
    { key = 'Impound', name = 'Impound', label = 'Impound', id = 25 },
    { key = 'Jewellery', name = 'Jewellery', label = 'Jewellery', id = 26 },
    { key = 'Job Garage', name = 'Job Garage', label = 'Job Garage', id = 27 },
    { key = 'Juice', name = 'Juice', label = 'Juice', id = 28 },
    { key = 'Liquor', name = 'Liquor', label = 'Liquor', id = 29 },
    { key = 'Mechanic', name = 'Mechanic', label = 'Mechanic', id = 30 },
    { key = 'Pharmacy', name = 'Pharmacy', label = 'Pharmacy', id = 31 },
    { key = 'Police', name = 'Police', label = 'Police', id = 32 },
    { key = 'Recycling', name = 'Recycling', label = 'Recycling', id = 33 },
    { key = 'Restaurant', name = 'Restaurant', label = 'Restaurant', id = 34 },
    { key = 'Scrapyard', name = 'Scrapyard', label = 'Scrapyard', id = 35 },
    { key = 'Tattoo', name = 'Tattoo', label = 'Tattoo', id = 36 },
    { key = 'Vehicle Dealer', name = 'Vehicle Dealer', label = 'Vehicle Dealer', id = 37 },
    { key = 'Vehicle Tracking', name = 'Vehicle Tracking', label = 'Vehicle Tracking', id = 38 },
    { key = 'Weapons', name = 'Weapons', label = 'Weapons', id = 39 },
    { key = 'Trucking', name = 'Trucking', label = 'Trucking', id = 40 },
}

local ALIASES = {
    ['ammu-nation'] = 'Weapons',
    ['clothing store'] = 'Clothing',
    ['tattoo artist'] = 'Tattoo',
    hairdresser = 'Grooming',
    barber = 'Grooming',
    ['police station'] = 'Police',
    ['dispatch calls'] = 'Dispatch',
    ["rob's liquor"] = 'Liquor',
}

---@param value string
---@return string label
local function normaliseLabel(value)
    assert(type(value) == 'string', 'Blip category/name/label must be a string.')
    local label = value:match('^%s*(.-)%s*$'):gsub('%s+', ' ')
    assert(label ~= '', 'Blip category/name/label must not be empty.')
    return label
end

---@param value string
---@return string lookup
local function lookupKey(value)
    return normaliseLabel(value):lower()
end

local byLookup = {}
local byId = {}
for index = 1, #DEFINITIONS do
    local definition = DEFINITIONS[index]
    byLookup[lookupKey(definition.key)] = definition
    byId[definition.id] = definition
end

for alias, category in pairs(ALIASES) do
    byLookup[lookupKey(alias)] = assert(byLookup[lookupKey(category)])
end

---@param category? string|number
---@return table definition
local function resolve(category)
    if category == nil then return byLookup.other end

    if type(category) == 'number' then
        assert(category >= 0 and category % 1 == 0, 'Blip category id must be a non-negative integer.')
        return byId[category] or {
            key = ('native:%d'):format(category),
            name = ('Category %d'):format(category),
            label = ('Category %d'):format(category),
            id = category,
            native = true,
        }
    end

    assert(type(category) == 'string', 'Blip category must be a name or numeric native id.')
    local normalised = normaliseLabel(category)
    local definition = byLookup[normalised:lower()]
    assert(definition, ("Unknown blip category '%s'. Use a category from Kora.blips.getCategories().")
        :format(normalised))
    return definition
end

-- Nested internal table: build/finalise exports only direct module functions,
-- so this shared catalogue is available to the client implementation without
-- accidentally publishing mutable internals as exports.
Kora.blips._categoryCatalog = {
    definitions = DEFINITIONS,
    byId = byId,
    normaliseLabel = normaliseLabel,
    resolve = resolve,
}

---Returns a fresh canonical category-name -> native-id map. The catalogue is
---available in both realms so server config/validation can share the same ids
---without reaching into client state.
---@return table<string, integer> categoryIds
function Kora.blips.getCategoryIds()
    local result = {}
    for index = 1, #DEFINITIONS do
        local definition = DEFINITIONS[index]
        result[definition.name] = definition.id
    end
    return result
end
