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

local function toGitHubPageUrl(rawUrl)
    local owner, repository, branch, filePath = rawUrl:match(
        '^https://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.*)$'
    )

    if not owner then return rawUrl end

    return ('https://github.com/%s/%s/blob/%s/%s'):format(owner, repository, branch, filePath)
end

local function printFailure(resource, message)
    print(('[kora_lib/versioncheck] %s: %s'):format(resource or 'unknown resource', message))
end

--- Checks the invoking resource's manifest version against a raw GitHub version file.
--- When it is out of date, prints a link to the corresponding GitHub patch-notes page.
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

        print(('%s is out of date: your version %s | current version %s'):format(
            resource, installedVersion, latestVersion
        ))
        print(('Update notes: %s'):format(toGitHubPageUrl(patchNotesUrl)))
    end, 'GET')

    return true
end
