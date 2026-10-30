local APP_ID = 'kora_lib:blips'
local TOGGLE_ACTION = 'kora_lib:blips:toggleCategory'
local BLIP_DOCS_URL = 'https://docs.fivem.net/docs/game-references/blips/'
local BLIP_ASSET_URL = 'https://docs-backend.fivem.net/blips/'

-- FiveM's image backend is keyed by the documented radar name, not the
-- numeric sprite id. Keep this deliberately curated to the sprites used by
-- first-party resources so an unknown/custom id never produces a broken URL.
local spriteDocs = {
    [1] = { name = 'radar_level', extension = 'png' },
    [8] = { name = 'radar_waypoint', extension = 'png' },
    [42] = { name = 'radar_police_chase', extension = 'gif' },
    [60] = { name = 'radar_police_station', extension = 'png' },
    [61] = { name = 'radar_hospital', extension = 'png' },
    [67] = { name = 'radar_security_van', extension = 'png' },
    [68] = { name = 'radar_tow_truck', extension = 'png' },
    [71] = { name = 'radar_barber', extension = 'png' },
    [73] = { name = 'radar_clothes_store', extension = 'png' },
    [75] = { name = 'radar_tattoo', extension = 'png' },
    [93] = { name = 'radar_bar', extension = 'png' },
    [106] = { name = 'radar_fbi_officers_strand', extension = 'png' },
    [108] = { name = 'radar_financier_strand', extension = 'png' },
    [110] = { name = 'radar_gun_shop', extension = 'png' },
    [141] = { name = 'radar_hunting', extension = 'png' },
    [161] = { name = 'radar_mp_noise', extension = 'gif' },
    [357] = { name = 'radar_garage', extension = 'png' },
    [365] = { name = 'radar_spawn_point_pickup', extension = 'png' },
    [380] = { name = 'radar_vehicle_deathmatch', extension = 'png' },
    [477] = { name = 'radar_truck', extension = 'png' },
    [499] = { name = 'radar_production_meth', extension = 'png' },
    [616] = { name = 'radar_bat_truck', extension = 'png' },
    [617] = { name = 'radar_bat_hack_jewel', extension = 'png' },
}

-- SetBlipColour uses FiveM's documented blip-colour table. These ids are not
-- interchangeable with the same-numbered entries in the separate HUD table.
local blipColours = {
    [0] = { name = 'White', hex = '#FEFEFE' },
    [1] = { name = 'Red', hex = '#E03232' },
    [2] = { name = 'Green', hex = '#71CB71' },
    [3] = { name = 'Blue', hex = '#5DB6E5' },
    [4] = { name = 'White', hex = '#FEFEFE' },
    [5] = { name = 'Yellow', hex = '#EEC64E' },
    [6] = { name = 'Light Red', hex = '#C25050' },
    [7] = { name = 'Violet', hex = '#9C6EAF' },
    [8] = { name = 'Pink', hex = '#FE7AC3' },
    [9] = { name = 'Light Orange', hex = '#F59D79' },
    [10] = { name = 'Light Brown', hex = '#B18F83' },
    [11] = { name = 'Light Green', hex = '#8DCEA7' },
    [12] = { name = 'Light Blue', hex = '#70A8AE' },
    [13] = { name = 'Light Purple', hex = '#D3D1E7' },
    [14] = { name = 'Dark Purple', hex = '#8F7E98' },
    [15] = { name = 'Cyan', hex = '#6AC4BF' },
    [16] = { name = 'Light Yellow', hex = '#D5C398' },
    [17] = { name = 'Orange', hex = '#EA8E50' },
    [18] = { name = 'Light Blue', hex = '#97CAE9' },
    [19] = { name = 'Dark Pink', hex = '#B26287' },
    [20] = { name = 'Dark Yellow', hex = '#8F8D79' },
    [21] = { name = 'Dark Orange', hex = '#A6755E' },
    [22] = { name = 'Light Gray', hex = '#AFA8A8' },
    [23] = { name = 'Light Pink', hex = '#E78D9A' },
    [24] = { name = 'Lemon Green', hex = '#BBD65B' },
    [25] = { name = 'Forest Green', hex = '#0C7B56' },
    [26] = { name = 'Electric Blue', hex = '#7AC3FE' },
    [27] = { name = 'Bright Purple', hex = '#AB3CE6' },
    [28] = { name = 'Dark Yellow', hex = '#CDA80C' },
    [29] = { name = 'Dark Blue', hex = '#4561AB' },
    [30] = { name = 'Dark Cyan', hex = '#29A5B8' },
    [31] = { name = 'Light Brown', hex = '#B89B7B' },
    [32] = { name = 'Light Blue', hex = '#C8E0FE' },
    [33] = { name = 'Light Yellow', hex = '#F0F096' },
    [34] = { name = 'Light Pink', hex = '#ED8CA1' },
    [35] = { name = 'Light Red', hex = '#F98A8A' },
    [36] = { name = 'Beige', hex = '#FBEEA5' },
    [37] = { name = 'White', hex = '#FEFEFE' },
    [38] = { name = 'Blue', hex = '#2C6DB8' },
    [39] = { name = 'Light Gray', hex = '#9A9A9A' },
    [40] = { name = 'Dark Gray', hex = '#4C4C4C' },
    [41] = { name = 'Pink Red', hex = '#F29D9D' },
    [42] = { name = 'Blue', hex = '#6CB7D6' },
    [43] = { name = 'Light Green', hex = '#AFEDAE' },
    [44] = { name = 'Light Orange', hex = '#FFA75F' },
    [45] = { name = 'White', hex = '#F1F1F1' },
    [46] = { name = 'Gold', hex = '#ECF029' },
    [47] = { name = 'Orange', hex = '#FF9A18' },
    [48] = { name = 'Brilliant Rose', hex = '#F644A5' },
    [49] = { name = 'Red', hex = '#E03A3A' },
    [50] = { name = 'Medium Purple', hex = '#8A6DE3' },
    [51] = { name = 'Salmon', hex = '#FF8B5C' },
    [52] = { name = 'Dark Green', hex = '#416C41' },
    [53] = { name = 'Blizzard Blue', hex = '#B3DDF3' },
    [54] = { name = 'Oracle Blue', hex = '#3A6479' },
    [55] = { name = 'Silver', hex = '#A0A0A0' },
    [56] = { name = 'Brown', hex = '#847232' },
    [57] = { name = 'Blue', hex = '#65B9E7' },
    [58] = { name = 'East Bay', hex = '#4B4175' },
    [59] = { name = 'Red', hex = '#E13B3B' },
    [60] = { name = 'Yellow Orange', hex = '#F0CB58' },
    [61] = { name = 'Mulberry Pink', hex = '#CD3F98' },
    [62] = { name = 'Alto Gray', hex = '#CFCFCF' },
    [63] = { name = 'Jelly Bean Blue', hex = '#276A9F' },
    [64] = { name = 'Dark Orange', hex = '#D87B1B' },
    [65] = { name = 'Mamba', hex = '#8E8393' },
    [66] = { name = 'Yellow Orange', hex = '#F0CB57' },
    [67] = { name = 'Blue', hex = '#65B9E7' },
    [68] = { name = 'Blue', hex = '#65B9E7' },
    [69] = { name = 'Green', hex = '#79CD79' },
    [70] = { name = 'Yellow Orange', hex = '#EFCA57' },
    [71] = { name = 'Yellow Orange', hex = '#EFCA57' },
    [72] = { name = 'Transparent Black', hex = '#3D3D3D' },
    [73] = { name = 'Yellow Orange', hex = '#EFCA57' },
    [74] = { name = 'Blue', hex = '#65B9E7' },
    [75] = { name = 'Red', hex = '#E03232' },
    [76] = { name = 'Deep Red', hex = '#782323' },
    [77] = { name = 'Blue', hex = '#65B9E7' },
    [78] = { name = 'Oracle Blue', hex = '#3A6479' },
    [79] = { name = 'Transparent Red', hex = '#E03232' },
    [80] = { name = 'Transparent Blue', hex = '#65B9E7' },
    [81] = { name = 'Orange', hex = '#F2A40C' },
    [82] = { name = 'Light Green', hex = '#A4CCAA' },
    [83] = { name = 'Purple', hex = '#A854F2' },
    [84] = { name = 'Blue', hex = '#65B9E7' },
    [85] = { name = 'Transparent Black', hex = '#3D3D3D' },
}

local categoryTargetByItem = {}
local viewerIsAdmin = false

local function normaliseLookup(value)
    if value == nil then return nil end
    return tostring(value):lower():gsub('^%s+', ''):gsub('%s+$', '')
end

local function readArray(fn)
    if type(fn) ~= 'function' then return {} end
    local ok, result = pcall(fn)
    return ok and type(result) == 'table' and result or {}
end

local function colourMetadata(index)
    local colour = blipColours[index]
    if colour then return ('%s · %d · %s'):format(colour.name, index, colour.hex) end
    return ('Unlisted blip colour · %s · Hex unavailable'):format(tostring(index))
end

local function blipLabel(blip, category)
    local name = blip.name
    local categoryName = normaliseLookup(category.name or category.key)
    if type(name) == 'string' and name ~= '' and normaliseLookup(name) ~= categoryName then return name end
    if type(blip.label) == 'string' and blip.label ~= '' then return blip.label end
    return ('Blip %s'):format(tostring(blip.handle or '?'))
end

local function blipItem(blip, category, sequence)
    local sprite = tonumber(blip.sprite) or 0
    local colourIndex = tonumber(blip.color) or 0
    local spriteInfo = spriteDocs[sprite]
    local metadata = {
        {
            label = 'Sprite',
            value = spriteInfo and ('%d · %s'):format(sprite, spriteInfo.name)
                or ('%d · Unlisted sprite'):format(sprite),
        },
        { label = 'Blip colour', value = colourMetadata(colourIndex) },
        { label = 'Display mode', value = tonumber(blip.display) or 'Default' },
        { label = 'FiveM docs', value = BLIP_DOCS_URL },
    }
    if viewerIsAdmin and type(blip.resource) == 'string' and blip.resource ~= '' then
        metadata[#metadata + 1] = { label = 'Owner resource', value = blip.resource }
    end

    local item = {
        id = ('blip:%s:%d'):format(tostring(blip.handle or 'unknown'), sequence),
        label = blipLabel(blip, category),
        description = blip.visible == false and 'Hidden from your map' or 'Visible on your map',
        badge = blip.visible == false and 'Hidden' or 'Visible',
        tone = blip.visible == false and 'neutral' or 'success',
        metadata = metadata,
    }
    if spriteInfo then
        item.image = ('%s%s.%s'):format(BLIP_ASSET_URL, spriteInfo.name, spriteInfo.extension)
    else
        item.icon = 'MapPin'
    end
    return item
end

local function categoryVisible(category, target)
    if type(category.visible) == 'boolean' then return category.visible end
    if type(QB.blips.isCategoryVisible) ~= 'function' then return true end
    local ok, visible = pcall(QB.blips.isCategoryVisible, target)
    return not ok or visible ~= false
end

local function buildNavigation()
    local categories = readArray(QB.blips.getCategories)
    local registered = readArray(QB.blips.getRegistered)
    local categoryById, categoryByName, childrenByCategory = {}, {}, {}
    categoryTargetByItem = {}

    for index = 1, #categories do
        local category = categories[index]
        if type(category) == 'table' then
            local key = tostring(category.id or category.name or category.key or index)
            childrenByCategory[key] = {}
            if category.id ~= nil then categoryById[tostring(category.id)] = key end
            local name = normaliseLookup(category.name)
            local catalogueKey = normaliseLookup(category.key)
            if name then categoryByName[name] = key end
            if catalogueKey then categoryByName[catalogueKey] = key end
        end
    end

    local unmatched = {}
    for index = 1, #registered do
        local blip = registered[index]
        if type(blip) == 'table' then
            local categoryKey = blip.category ~= nil and categoryById[tostring(blip.category)] or nil
            categoryKey = categoryKey or categoryByName[normaliseLookup(blip.categoryKey)]
            if not categoryKey and blip.category == nil then
                categoryKey = categoryByName[normaliseLookup(blip.name)]
            end
            local target = categoryKey and childrenByCategory[categoryKey] or unmatched
            target[#target + 1] = blip
        end
    end

    local items = {}
    for index = 1, #categories do
        local category = categories[index]
        if type(category) == 'table' then
            local key = tostring(category.id or category.name or category.key or index)
            local target = category.id or category.name or category.key
            local visible = categoryVisible(category, target)
            local records = childrenByCategory[key] or {}
            table.sort(records, function(a, b)
                return blipLabel(a, category):lower() < blipLabel(b, category):lower()
            end)

            local children = {}
            for childIndex = 1, #records do
                children[#children + 1] = blipItem(records[childIndex], category, childIndex)
            end

            local itemId = 'category:' .. key
            categoryTargetByItem[itemId] = target
            local count = #children
            local item = {
                id = itemId,
                label = tostring(category.label or category.name or category.key or ('Category ' .. key)),
                description = count == 1 and '1 registered blip' or ('%d registered blips'):format(count),
                badge = visible and 'Visible' or 'Hidden',
                tone = visible and 'success' or 'neutral',
                metadata = { { label = 'Category', value = category.id or category.name or category.key or key } },
                actions = { {
                    id = TOGGLE_ACTION,
                    label = visible and 'Hide category' or 'Show category',
                    icon = visible and 'X' or 'Check',
                    variant = 'outline',
                    state = visible,
                } },
            }
            if #children > 0 then item.children = children end
            items[#items + 1] = item
        end
    end

    if #unmatched > 0 then
        local children = {}
        local fallbackCategory = { name = 'Uncategorised' }
        for index = 1, #unmatched do children[#children + 1] = blipItem(unmatched[index], fallbackCategory, index) end
        items[#items + 1] = {
            id = 'category:unmatched',
            label = 'Uncategorised',
            description = #children == 1 and '1 registered blip' or ('%d registered blips'):format(#children),
            badge = 'Individual',
            icon = 'MapPin',
            children = children,
        }
    end

    if #items == 0 then
        return { {
            id = 'categories',
            label = 'Categories',
            icon = 'MapPin',
            content = { blocks = { {
                type = 'empty',
                title = 'No blip categories available',
                description = 'Registered kora_lib blips will appear here automatically.',
                icon = 'MapPin',
            } } },
        } }
    end

    return { {
        id = 'categories',
        label = 'Categories',
        icon = 'MapPin',
        content = {
            title = 'Map blips',
            description = 'Choose which categories appear on your map. Your choices are saved on this client.',
            blocks = { {
                type = 'list',
                id = 'blip-categories',
                searchable = true,
                searchPlaceholder = 'Search categories or blips…',
                pageSize = 12,
                items = items,
            } },
        },
    } }
end

local function refreshApp()
    return QB.nui.updateApp(APP_ID, { navigation = buildNavigation() })
end

local function actionError(message)
    return { notice = { tone = 'destructive', message = message } }
end

local function onAction(actionId, context)
    if actionId ~= TOGGLE_ACTION then return actionError('That blip action is no longer available.') end
    local target = type(context) == 'table' and categoryTargetByItem[context.itemId] or nil
    if target == nil then return actionError('That blip category is no longer available.') end

    local visibleOk, visible = pcall(QB.blips.isCategoryVisible, target)
    if not visibleOk then return actionError('The category state could not be read.') end
    local operation = visible and QB.blips.hideCategory or QB.blips.showCategory
    if type(operation) ~= 'function' then return actionError('Category visibility is not available.') end

    local changedOk, _, err = pcall(operation, target)
    if not changedOk then return actionError('The category could not be updated.') end
    if err ~= nil then return actionError(tostring(err)) end

    refreshApp()
    local categoryOk, category = pcall(QB.blips.getCategory, target)
    local label = categoryOk and category and (category.label or category.name or category.key) or tostring(target)
    return {
        notice = {
            tone = 'success',
            message = ('%s blips %s.'):format(tostring(label), visible and 'hidden' or 'shown'),
        },
    }
end

QB.nui.registerApp({
    id = APP_ID,
    title = 'Blip settings',
    description = 'Personalise the map without affecting other players.',
    icon = 'MapPin',
    layout = 'compact',
    placement = 'center',
    width = 760,
    height = 760,
    navigation = buildNavigation(),
    footer = 'Press X or Escape to close',
    onAction = onAction,
})

local opening = false
RegisterCommand('blips', function()
    if QB.nui.isAppOpen(APP_ID) then
        QB.nui.closeApp(APP_ID)
        return
    end
    if opening then return end
    opening = true

    CreateThread(function()
        local ok, isAdmin = pcall(function()
            return Citizen.Await(QB.callback.trigger('kora_lib:blips:isAdmin'))
        end)
        viewerIsAdmin = ok and isAdmin == true
        refreshApp()

        local opened, err = pcall(QB.nui.openApp, APP_ID)
        opening = false
        if not opened then print(('[kora_lib:blips] settings could not open: %s'):format(tostring(err))) end
    end)
end, false)
