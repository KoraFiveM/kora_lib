-- Compatibility adapter: keep variadic print names, route through the logger.
-- Tables remain structured fields so recursive redaction cannot be bypassed.
for name, level in pairs({ debug = 'debug', info = 'info', warn = 'warn', error = 'error', success = 'info' }) do
    Kora.print[name] = function(...)
        local messages, values = {}, {}
        for index = 1, select('#', ...) do
            local value = select(index, ...)
            if type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' then
                messages[#messages + 1] = tostring(value)
            else
                values[tostring(index)] = value
            end
        end
        return Kora.logging[level]('legacy.print', table.concat(messages, ' '), values)
    end
end
