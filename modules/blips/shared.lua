local DEFINITIONS = {
    { key = 'Other', name = 'Other', label = KoraLang('Modules.Blips.categories.other'), id = 12 },
    { key = 'Bank', name = 'Bank', label = KoraLang('Modules.Blips.categories.bank'), id = 13 },
    { key = 'Bar', name = 'Bar', label = KoraLang('Modules.Blips.categories.bar'), id = 14 },
    { key = 'Business', name = 'Business', label = KoraLang('Modules.Blips.categories.business'), id = 15 },
    { key = 'Clothing', name = 'Clothing', label = KoraLang('Modules.Blips.categories.clothing'), id = 16 },
    { key = 'Convenience', name = 'Convenience', label = KoraLang('Modules.Blips.categories.convenience'), id = 17 },
    { key = 'Dispatch', name = 'Dispatch', label = KoraLang('Modules.Blips.categories.dispatch'), id = 18 },
    { key = 'Evidence', name = 'Evidence', label = KoraLang('Modules.Blips.categories.evidence'), id = 19 },
    { key = 'Fuel', name = 'Fuel', label = KoraLang('Modules.Blips.categories.fuel'), id = 20 },
    { key = 'Garage', name = 'Garage', label = KoraLang('Modules.Blips.categories.garage'), id = 21 },
    { key = 'Gang Garage', name = 'Gang Garage', label = KoraLang('Modules.Blips.categories.gang_garage'), id = 22 },
    { key = 'Grooming', name = 'Grooming', label = KoraLang('Modules.Blips.categories.grooming'), id = 23 },
    { key = 'Hospital', name = 'Hospital', label = KoraLang('Modules.Blips.categories.hospital'), id = 24 },
    { key = 'Impound', name = 'Impound', label = KoraLang('Modules.Blips.categories.impound'), id = 25 },
    { key = 'Jewellery', name = 'Jewellery', label = KoraLang('Modules.Blips.categories.jewellery'), id = 26 },
    { key = 'Job Garage', name = 'Job Garage', label = KoraLang('Modules.Blips.categories.job_garage'), id = 27 },
    { key = 'Juice', name = 'Juice', label = KoraLang('Modules.Blips.categories.juice'), id = 28 },
    { key = 'Liquor', name = 'Liquor', label = KoraLang('Modules.Blips.categories.liquor'), id = 29 },
    { key = 'Mechanic', name = 'Mechanic', label = KoraLang('Modules.Blips.categories.mechanic'), id = 30 },
    { key = 'Pharmacy', name = 'Pharmacy', label = KoraLang('Modules.Blips.categories.pharmacy'), id = 31 },
    { key = 'Police', name = 'Police', label = KoraLang('Modules.Blips.categories.police'), id = 32 },
    { key = 'Recycling', name = 'Recycling', label = KoraLang('Modules.Blips.categories.recycling'), id = 33 },
    { key = 'Restaurant', name = 'Restaurant', label = KoraLang('Modules.Blips.categories.restaurant'), id = 34 },
    { key = 'Scrapyard', name = 'Scrapyard', label = KoraLang('Modules.Blips.categories.scrapyard'), id = 35 },
    { key = 'Tattoo', name = 'Tattoo', label = KoraLang('Modules.Blips.categories.tattoo'), id = 36 },
    { key = 'Vehicle Dealer', name = 'Vehicle Dealer',
        label = KoraLang('Modules.Blips.categories.vehicle_dealer'), id = 37 },
    { key = 'Vehicle Tracking', name = 'Vehicle Tracking',
        label = KoraLang('Modules.Blips.categories.vehicle_tracking'), id = 38 },
    { key = 'Weapons', name = 'Weapons', label = KoraLang('Modules.Blips.categories.weapons'), id = 39 },
    { key = 'Trucking', name = 'Trucking', label = KoraLang('Modules.Blips.categories.trucking'), id = 40 },
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
    assert(type(value) == 'string', KoraLang('Modules.Blips.category_text_string'))
    local label = value:match('^%s*(.-)%s*$'):gsub('%s+', ' ')
    assert(label ~= '', KoraLang('Modules.Blips.category_text_empty'))
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
        assert(category >= 0 and category % 1 == 0, KoraLang('Modules.Blips.category_id_invalid'))
        return byId[category] or {
            key = ('native:%d'):format(category),
            name = KoraLang('Modules.Blips.native_category', category),
            label = KoraLang('Modules.Blips.native_category', category),
            id = category,
            native = true,
        }
    end

    assert(type(category) == 'string', KoraLang('Modules.Blips.category_invalid'))
    local normalised = normaliseLabel(category)
    local definition = byLookup[normalised:lower()]
    assert(definition, KoraLang('Modules.Blips.unknown_category', normalised))
    return definition
end

Kora.blips._categoryCatalog = {
    definitions = DEFINITIONS,
    byId = byId,
    normaliseLabel = normaliseLabel,
    resolve = resolve,
}

---Returns a fresh canonical category-name -> native-id map (shared so server config can validate).
---@return table<string, integer> categoryIds
function Kora.blips.getCategoryIds()
    local result = {}
    for index = 1, #DEFINITIONS do
        local definition = DEFINITIONS[index]
        result[definition.name] = definition.id
    end
    return result
end
