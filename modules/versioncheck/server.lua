local function normalizeVersion(value)
    if type(value) ~= 'string' then return nil end

    local version = value:match('^%s*(.-)%s*$')
    version = version and version:gsub('^[vV]', '')
    if not version or not version:match('^%d+%.%d+%.%d+[%w%.%+%-]*$') then return nil end

    return version
end

--- Compares two normalized versions: -1 when left is older, 0 when equal,
--- 1 when left is newer. The suffix decides the semver way: a release
--- outranks any pre-release of the same core, and pre-release tokens order
--- numerically when both are numbers ('dev.3' < 'dev.4').
local function compareVersions(left, right)
    local aMajor, aMinor, aPatch, aSuffix = left:match('^(%d+)%.(%d+)%.(%d+)(.*)$')
    local bMajor, bMinor, bPatch, bSuffix = right:match('^(%d+)%.(%d+)%.(%d+)(.*)$')
    if not aMajor or not bMajor then
        return left == right and 0 or (left < right and -1 or 1)
    end

    local aCore = { tonumber(aMajor), tonumber(aMinor), tonumber(aPatch) }
    local bCore = { tonumber(bMajor), tonumber(bMinor), tonumber(bPatch) }
    for i = 1, 3 do
        if aCore[i] ~= bCore[i] then
            return aCore[i] < bCore[i] and -1 or 1
        end
    end

    local aTokens, bTokens = {}, {}
    for token in aSuffix:gmatch('[^%.%+%-%s]+') do
        aTokens[#aTokens + 1] = token
    end
    for token in bSuffix:gmatch('[^%.%+%-%s]+') do
        bTokens[#bTokens + 1] = token
    end

    -- A release (no tokens) outranks any pre-release; more shared tokens = newer.
    local longest = #aTokens > #bTokens and #aTokens or #bTokens
    for i = 1, longest do
        local a, b = aTokens[i], bTokens[i]
        if a ~= b then
            if a == nil then
                if #aTokens == 0 then
                    return 1
                end
                return -1
            end
            if b == nil then
                if #bTokens == 0 then
                    return -1
                end
                return 1
            end

            local aNumber, bNumber = tonumber(a), tonumber(b)
            if aNumber ~= nil and bNumber ~= nil then
                return aNumber < bNumber and -1 or 1
            end
            if aNumber ~= nil then
                return -1
            end
            if bNumber ~= nil then
                return 1
            end
            return a < b and -1 or 1
        end
    end

    return 0
end

local function readManifestVersion(manifest)
    for line in manifest:gmatch('[^\r\n]+') do
        local declared = line:match([[^%s*version%s+['"]([^'"]+)['"]%s*$]])
            or line:match([[^%s*version%s*%(%s*['"]([^'"]+)['"]%s*%)%s*$]])
            or line:match([[^%s*version%s*=%s*['"]([^'"]+)['"]%s*$]])
        local version = normalizeVersion(declared)
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

--- Checks the invoking resource's manifest version against a raw GitHub fxmanifest.lua.
--- When it is out of date, prints a link to the corresponding GitHub patch-notes page.
---@param remoteManifestUrl string Raw URL for the latest fxmanifest.lua.
---@param patchNotesUrl string Raw URL for a Markdown patch-notes file.
---@return boolean started Whether the asynchronous version request was started.
function Kora.versioncheck.check(remoteManifestUrl, patchNotesUrl)
    assert(type(remoteManifestUrl) == 'string' and remoteManifestUrl ~= '', 'remoteManifestUrl must be a non-empty string.')
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

    PerformHttpRequest(remoteManifestUrl, function(statusCode, body, _, errorData)
        if statusCode ~= 200 or type(body) ~= 'string' then
            printFailure(resource, ('could not fetch remote fxmanifest.lua (HTTP %s): %s'):format(
                tostring(statusCode), tostring(errorData or 'no response body')
            ))
            return
        end

        local latestVersion = readManifestVersion(body)
        if not latestVersion then
            printFailure(resource, 'remote fxmanifest.lua does not contain a valid version declaration.')
            return
        end

        -- Only an older installed version is out of date. A resource running
        -- ahead of the published manifest (a PR branch, a local test build)
        -- is not, so the comparison must understand versions rather than
        -- treat them as opaque strings.
        if compareVersions(installedVersion, latestVersion) >= 0 then
            return
        end

        print(('%s is out of date: your version %s | current version %s'):format(
            resource, installedVersion, latestVersion
        ))
        print(('Update notes: %s'):format(toGitHubPageUrl(patchNotesUrl)))
    end, 'GET')

    return true
end
