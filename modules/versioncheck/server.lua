local function normalizeVersion(value)
    if type(value) ~= 'string' then return nil end

    local version = value:match('^%s*(.-)%s*$')
    version = version and version:gsub('^[vV]', '')
    if not version or not version:match('^%d+%.%d+%.%d+[%w%.%+%-]*$') then return nil end

    return version
end

local function readRemoteVersion(versionText)
    local version = normalizeVersion(versionText)
    if version then return version end

    for line in versionText:gmatch('[^\r\n]+') do
        local declared = line:match([[^%s*version%s*[:=]?%s*['"]?([^'"]+)['"]?%s*$]])
        version = normalizeVersion(declared)
        if version then return version end
    end
end

local function getMissingPatchNotes(patchNotes, installedVersion, latestVersion)
    local sections = {}
    local currentSection

    for line in patchNotes:gmatch('[^\r\n]+') do
        local indent, _, heading = line:match('^(%s*)([%-%*])%s+(.+)$')
        if indent == '' then
            local version = normalizeVersion(heading)
            if version then
                currentSection = { version = version, details = {} }
                sections[#sections + 1] = currentSection
            else
                currentSection = nil
            end
        elseif currentSection then
            local detail = line:match('^%s+(.+)$')
            if detail then
                detail = detail:gsub('^[%-%*]%s+', '')
                if detail ~= '' then
                    currentSection.details[#currentSection.details + 1] = detail
                end
            end
        end
    end

    local installedIndex
    local latestIndex
    for index, section in ipairs(sections) do
        if section.version == installedVersion then installedIndex = index end
        if section.version == latestVersion then latestIndex = index end
    end

    installedIndex = installedIndex or 0
    latestIndex = latestIndex or #sections
    if latestIndex <= installedIndex then return {} end

    local missing = {}
    for index = installedIndex + 1, latestIndex do
        for _, detail in ipairs(sections[index].details) do
            missing[#missing + 1] = detail
        end
    end

    return missing
end

local function printFailure(resource, message)
    print(('[kora_lib/versioncheck] %s: %s'):format(resource or 'unknown resource', message))
end

--- Checks the invoking resource's manifest version against a raw GitHub version file.
--- If versions differ, it prints patch-note details newer than the installed version.
---@param remoteVersionUrl string Raw URL containing the latest version number.
---@param patchNotesUrl string Raw URL for a Markdown patch-notes file.
---@return boolean started Whether the asynchronous version request was started.
function Kora.versioncheck.check(remoteVersionUrl, patchNotesUrl)
    assert(type(remoteVersionUrl) == 'string' and remoteVersionUrl ~= '', 'remoteVersionUrl must be a non-empty string.')
    assert(type(patchNotesUrl) == 'string' and patchNotesUrl ~= '', 'patchNotesUrl must be a non-empty string.')

    local resource = GetInvokingResource() or GetCurrentResourceName()
    if not resource then
        printFailure(nil, 'check must be called from another resource.')
        return false
    end

    local installedVersion = normalizeVersion(GetResourceMetadata(resource, 'version', 0))
    if not installedVersion then
        printFailure(resource, 'no valid version metadata was found in its fxmanifest.lua.')
        return false
    end

    PerformHttpRequest(remoteVersionUrl, function(statusCode, body, _, errorData)
        if statusCode ~= 200 or type(body) ~= 'string' then
            printFailure(resource, ('could not fetch remote version file (HTTP %s): %s'):format(
                tostring(statusCode), tostring(errorData or 'no response body')
            ))
            return
        end

        local latestVersion = readRemoteVersion(body)
        if not latestVersion then
            printFailure(resource, 'remote version file does not contain a valid version.')
            return
        end

        if installedVersion == latestVersion then return end

        PerformHttpRequest(patchNotesUrl, function(notesStatus, notesBody, _, notesError)
            if notesStatus ~= 200 or type(notesBody) ~= 'string' then
                print(('%s is out of date: your version %s | current version %s'):format(
                    resource, installedVersion, latestVersion
                ))
                printFailure(resource, ('could not fetch patch notes (HTTP %s): %s'):format(
                    tostring(notesStatus), tostring(notesError or 'no response body')
                ))
                return
            end

            print(('%s is out of date: your version %s | current version %s'):format(
                resource, installedVersion, latestVersion
            ))

            for _, detail in ipairs(getMissingPatchNotes(notesBody, installedVersion, latestVersion)) do
                print(detail)
            end
        end, 'GET')
    end, 'GET')

    return true
end
