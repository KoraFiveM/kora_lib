local function parseVersion(value)
    if type(value) ~= 'string' then return nil end

    local major, minor, patch = value:match('^[vV]?(%d+)%.(%d+)%.(%d+)')
    if not major then return nil end

    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function compareVersions(left, right)
    for index = 1, 3 do
        if left[index] ~= right[index] then
            return left[index] < right[index] and -1 or 1
        end
    end

    return 0
end

local function readManifestVersion(manifest)
    for line in manifest:gmatch('[^\r\n]+') do
        local version = line:match([[^%s*version%s*['"]([^'"]+)['"]])
            or line:match([[^%s*version%s*%(%s*['"]([^'"]+)['"]%s*%)])
        if version then return version end
    end
end

local function getMissingPatchNotes(patchNotes, installedVersion, latestVersion)
    local installed = parseVersion(installedVersion)
    local latest = parseVersion(latestVersion)
    if not installed or not latest then return {} end

    local missing = {}
    local sectionVersion
    local sectionIsMissing = false

    for line in patchNotes:gmatch('[^\r\n]+') do
        local indent, bullet = line:match('^(%s*)([-*]%s+)(.+)$')
        if indent == '' and bullet then
            local versionText = line:match('^[-*]%s+[vV]?(%d+%.%d+%.%d+)%s*$')
            sectionVersion = versionText and parseVersion(versionText) or nil
            sectionIsMissing = sectionVersion ~= nil
                and compareVersions(sectionVersion, installed) > 0
                and compareVersions(sectionVersion, latest) <= 0
        elseif sectionIsMissing then
            local detail = line:match('^%s+(.+)$')
            if detail then
                detail = detail:gsub('^[-*]%s+', '')
                if detail ~= '' then missing[#missing + 1] = detail end
            end
        end
    end

    return missing
end

local function printFailure(resource, message)
    print(('[kora_lib/versioncheck] %s: %s'):format(resource or 'unknown resource', message))
end

--- Checks the invoking resource's manifest version against a raw GitHub fxmanifest.lua.
--- If versions differ, it prints patch-note details newer than the installed version.
---@param remoteManifestUrl string Raw URL for the latest fxmanifest.lua.
---@param patchNotesUrl string Raw URL for a Markdown patch-notes file.
---@return boolean started Whether the asynchronous version request was started.
function Kora.versioncheck.check(remoteManifestUrl, patchNotesUrl)
    assert(type(remoteManifestUrl) == 'string' and remoteManifestUrl ~= '', 'remoteManifestUrl must be a non-empty string.')
    assert(type(patchNotesUrl) == 'string' and patchNotesUrl ~= '', 'patchNotesUrl must be a non-empty string.')

    local resource = GetInvokingResource()
    if not resource then
        printFailure(nil, 'check must be called from another resource.')
        return false
    end

    local installedVersion = GetResourceMetadata(resource, 'version', 0)
    if type(installedVersion) ~= 'string' or installedVersion == '' then
        printFailure(resource, 'no version metadata was found in its fxmanifest.lua.')
        return false
    end

    PerformHttpRequest(remoteManifestUrl, function(statusCode, body, _, errorData)
        if statusCode ~= 200 or type(body) ~= 'string' then
            printFailure(resource, ('could not fetch remote fxmanifest.lua (HTTP %s): %s'):format(
                tostring(statusCode), tostring(errorData or 'no response body')
            ))
            return
        end

        local latestVersion = readManifestVersion(body)
        if not latestVersion then
            printFailure(resource, 'remote fxmanifest.lua does not declare a version.')
            return
        end

        if installedVersion == latestVersion then return end

        PerformHttpRequest(patchNotesUrl, function(notesStatus, notesBody, _, notesError)
            if notesStatus ~= 200 or type(notesBody) ~= 'string' then
                printFailure(resource, ('%s is out of date: your version %s | current version %s'):format(
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
