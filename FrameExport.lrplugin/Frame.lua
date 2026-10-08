-- Pure Lua helpers, also exercised outside Lightroom by tests/run.lua.
local Frame = {}

function Frame.validate(width, color, executable)
    width = tonumber(width)
    if not width or width ~= width or width < 0 or width > 200 then
        return nil, 'Percentage must be a number from 0 to 200 (use a decimal point).'
    end
    if type(color) ~= 'string' or not color:match('^#%x%x%x%x%x%x$') then
        return nil, 'Color must use #RRGGBB format, for example #FFFFFF.'
    end
    executable = executable or ''
    if type(executable) ~= 'string' then
        return nil, 'Invalid ImageMagick path.'
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
    assert(not value:find('[%z\r\n]'), 'Invalid character in path')
    if windows then
        -- cmd.exe expands these even inside quotes. Refuse rather than execute
        -- an unexpected command or silently address a different file.
        assert(not value:find('["%%!]'), 'Windows paths cannot contain ", % or !')
        return '"' .. value .. '"'
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function Frame.command(options, input, output, log, windows, format, quality)
    local quote = function(v) return Frame.quote(v, windows) end
    assert(options.pixelWidth and options.pixelHeight, 'Missing export dimensions')
    local horizontal = math.floor(options.pixelWidth * options.width / 200 + 0.5)
    local vertical = horizontal
    local parts = { quote(options.executable), quote(input),
        '-bordercolor', quote(options.color),
        '-border', quote(tostring(horizontal) .. 'x' .. tostring(vertical)) }
    if format == 'JPEG' then
        quality = tonumber(quality) or 0.9
        assert(quality >= 0 and quality <= 1, 'Invalid JPEG quality')
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
    assert(w and h, 'Could not read export dimensions from ImageMagick.')
    return tonumber(w), tonumber(h)
end

return Frame
