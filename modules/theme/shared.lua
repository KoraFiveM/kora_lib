local DEFAULT_ACCENT_COLOR = "#DC143C"

-- Ported line-for-line from web/src/components/theme/ThemeSynchronizer.tsx's
-- applyAccentColor/hslFromHex/relativeLuminance -- same magic numbers, same
-- derivation order. If one changes, change both, and re-check
-- test/smoke/theme.lua's parity assertions against web/src/styles/globals.css.

local function channelLuminance(value)
    local normalized = value / 255
    if normalized <= 0.04045 then
        return normalized / 12.92
    end
    return ((normalized + 0.055) / 1.055) ^ 2.4
end

local function relativeLuminance(red, green, blue)
    return 0.2126 * channelLuminance(red) + 0.7152 * channelLuminance(green) + 0.0722 * channelLuminance(blue)
end

-- The #101010 overlay background's luminance, computed once at load -- the
-- reference surface QB.theme.tokens() contrasts a solid-brand foreground
-- against when deciding between white and near-black text.
local DARK_SURFACE_LUMINANCE = relativeLuminance(16, 16, 16)

-- Lua has no Math.round; JS's Math.round rounds half-up, which
-- math.floor(x*10+0.5)/10 matches exactly for non-negative x -- hue/
-- saturation/lightness here are never negative, so this is safe despite not
-- handling negative inputs correctly.
local function round1(value)
    return math.floor(value * 10 + 0.5) / 10
end

local function hslFromHex(red, green, blue)
    red, green, blue = red / 255, green / 255, blue / 255
    local max = math.max(red, green, blue)
    local min = math.min(red, green, blue)
    local delta = max - min
    local lightness = (max + min) / 2

    local hue = 0
    if delta ~= 0 then
        if max == red then
            hue = ((green - blue) / delta) % 6
        elseif max == green then
            hue = (blue - red) / delta + 2
        else
            hue = (red - green) / delta + 4
        end
        hue = hue * 60
        if hue < 0 then hue = hue + 360 end
    end

    local saturation = delta == 0 and 0 or delta / (1 - math.abs(2 * lightness - 1))

    return round1(hue), round1(saturation * 100), round1(lightness * 100)
end

-- Formats a number the way JS's template-literal string coercion would --
-- "348", not Lua's default tostring(348.0) == "348.0" -- so the resulting
-- token strings byte-for-byte match what ThemeSynchronizer.tsx produces.
local function numToStr(value)
    if value == math.floor(value) then
        return ("%d"):format(value)
    end
    return ("%.1f"):format(value)
end

-- `alpha` (0.14 / 0.45) is a fixed literal passed straight through by every
-- call site below, not a rounded hue/saturation/lightness value -- so it's
-- interpolated as-is, same as the TS template literal does.
local function hslToken(hue, saturation, lightness, alpha)
    if alpha == nil then
        return ("%s %s%% %s%%"):format(numToStr(hue), numToStr(saturation), numToStr(lightness))
    end
    return ("%s %s%% %s%% / %s"):format(numToStr(hue), numToStr(saturation), numToStr(lightness), tostring(alpha))
end

---Validates and returns the configured brand accent colour (`Config.ui.accentColor`),
---falling back to the default crimson (and logging a warning) if it's missing or
---malformed. The one place that reads/validates this config value -- both the
---NUI theme callback and QB.theme.tokens() go through this instead of each
---reading Config.ui directly.
---@return string hex `#RRGGBB`
function QB.theme.accentColor()
    local configured = Config and Config.ui and Config.ui.accentColor
    if type(configured) == "string" and configured:match("^#%x%x%x%x%x%x$") then
        return configured
    end

    if configured ~= nil then
        print("[qblib:theme] Config.ui.accentColor must be a #RRGGBB hex colour; using #DC143C.")
    end

    return DEFAULT_ACCENT_COLOR
end

---Derives the full semantic HSL design-token set from an accent colour, ready
---to apply directly as CSS custom properties (`--primary`, `--brand-hover`,
---etc.) in any consuming resource's own NUI -- no HSL math needs to be
---reimplemented per-resource. Values are `"H S% L%"` / `"H S% L% / A"`
---strings, matching web/src/styles/globals.css's variable format exactly.
---@param accentColor? string `#RRGGBB`; defaults to QB.theme.accentColor()
---@return table<string, string> tokens
function QB.theme.tokens(accentColor)
    local hex = accentColor or QB.theme.accentColor()
    if type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x$") then
        hex = DEFAULT_ACCENT_COLOR
    end

    local red = tonumber(hex:sub(2, 3), 16)
    local green = tonumber(hex:sub(4, 5), 16)
    local blue = tonumber(hex:sub(6, 7), 16)

    local hue, saturation, lightness = hslFromHex(red, green, blue)
    local primary = hslToken(hue, saturation, lightness)

    local luminance = relativeLuminance(red, green, blue)
    local whiteContrast = 1.05 / (luminance + 0.05)
    local darkContrast = (luminance + 0.05) / (DARK_SURFACE_LUMINANCE + 0.05)

    return {
        primary = primary,
        ring = primary,
        ["brand-hover"] = hslToken(hue, saturation, math.max(0, lightness - 5.1)),
        ["brand-pressed"] = hslToken(hue, saturation, math.max(0, lightness - 10.6)),
        ["brand-soft"] = hslToken(hue, saturation, lightness, 0.14),
        ["brand-border"] = hslToken(hue, saturation, lightness, 0.45),
        ["primary-foreground"] = (whiteContrast >= darkContrast) and "0 0% 100%" or "0 0% 6.3%",
    }
end
