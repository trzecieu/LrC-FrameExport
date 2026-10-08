-- Pure Lua helpers, also exercised outside Lightroom by tests/run.lua.
local Frame = {}

function Frame.validate(width, color, executable)
    width = tonumber(width)
    if not width or width ~= width or width < 0 or width > 200 then
        return nil, 'Procent musi być liczbą od 0 do 200 (użyj kropki dziesiętnej).'
    end
    if type(color) ~= 'string' or not color:match('^#%x%x%x%x%x%x$') then
        return nil, 'Kolor musi mieć postać #RRGGBB, np. #FFFFFF.'
    end
    executable = executable or ''
    if type(executable) ~= 'string' then
        return nil, 'Nieprawidłowa ścieżka ImageMagick.'
    end
    return { width = width, color = color, executable = executable }
end

function Frame.hexToRgb(value)
    if type(value) ~= 'string' or not value:match('^#%x%x%x%x%x%x$') then return nil end
    return tonumber(value:sub(2, 3), 16) / 255,
        tonumber(value:sub(4, 5), 16) / 255, tonumber(value:sub(6, 7), 16) / 255
end

function Frame.rgbToHex(red, green, blue)
    local byte = function(value)
        return math.floor(math.max(0, math.min(1, value)) * 255 + 0.5)
    end
    return string.format('#%02X%02X%02X', byte(red), byte(green), byte(blue))
end

function Frame.quote(value, windows)
    assert(type(value) == 'string', 'Expected a string')
    assert(not value:find('[%z\r\n]'), 'Niedozwolony znak w ścieżce')
    if windows then
        -- cmd.exe expands these even inside quotes. Refuse rather than execute
        -- an unexpected command or silently address a different file.
        assert(not value:find('["%%!]'), 'Ścieżki Windows nie mogą zawierać znaków ", % ani !')
        return '"' .. value .. '"'
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function Frame.command(options, input, output, log, windows, format, quality)
    local quote = function(v) return Frame.quote(v, windows) end
    assert(options.pixelWidth and options.pixelHeight, 'Brak wymiarów eksportu')
    local horizontal = math.floor(options.pixelWidth * options.width / 200 + 0.5)
    local vertical = horizontal
    local parts = { quote(options.executable), quote(input),
        '-bordercolor', quote(options.color),
        '-border', quote(tostring(horizontal) .. 'x' .. tostring(vertical)) }
    if format == 'JPEG' then
        quality = tonumber(quality) or 0.9
        assert(quality >= 0 and quality <= 1, 'Nieprawidłowa jakość JPEG')
        parts[#parts + 1] = '-quality'
        parts[#parts + 1] = tostring(math.floor(quality * 100 + 0.5))
    elseif format == 'TIFF' then
        parts[#parts + 1] = '-compress'
        parts[#parts + 1] = 'Zip'
    end
    parts[#parts + 1] = quote(output)
    local command = table.concat(parts, ' ') .. ' > ' .. quote(log) .. ' 2>&1'
    if windows then command = '"' .. command .. '"' end
    return command
end

function Frame.identifyCommand(executable, input, log, windows)
    local quote = function(v) return Frame.quote(v, windows) end
    local command = quote(executable) .. ' identify -ping -verbose ' .. quote(input) ..
        ' > ' .. quote(log) .. ' 2>&1'
    if windows then command = '"' .. command .. '"' end
    return command
end

function Frame.dimensions(report)
    local w, h = report:match('Geometry: (%d+)x(%d+)')
    assert(w and h, 'Nie można odczytać wymiarów eksportu z ImageMagick.')
    return tonumber(w), tonumber(h)
end

return Frame
