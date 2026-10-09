-- Pure Lua helpers, also exercised outside Lightroom by tests/run.lua.
local Frame = {}

function Frame.validate(width, color, executable, mode)
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
    mode = mode or 'outside'
    if mode ~= 'outside' and mode ~= 'inside' and mode ~= 'outside_fit' then
        return nil, 'Unknown border type. Select Outside, Inside or Outside (keep dimensions).'
    end
    return { width = width, color = color, executable = executable, mode = mode }
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
    local parts = { quote(options.executable), quote(input) }
    local function add(...)
        for _, part in ipairs({ ... }) do parts[#parts + 1] = part end
    end
    local mode = options.mode or 'outside'
    assert(mode == 'outside' or mode == 'inside' or mode == 'outside_fit', 'Unknown border type')
    if mode == 'outside' then
        add('-bordercolor', quote(options.color), '-border', quote(horizontal .. 'x' .. horizontal))
    else
        local width, height = options.pixelWidth, options.pixelHeight
        local innerWidth, innerHeight = width - 2 * horizontal, height - 2 * horizontal
        assert(innerWidth > 0 and innerHeight > 0,
            'The border is too thick for this image in a fixed-dimensions mode. Reduce the percentage.')
        if mode == 'inside' and horizontal > 0 then
            -- Replace the edge pixels with an opaque border, without resampling
            -- the interior or introducing a vector drawing alpha channel.
            local border = quote(horizontal .. 'x' .. horizontal)
            add('-shave', border, '+repage', '-bordercolor', quote(options.color), '-border', border)
        elseif mode == 'outside_fit' then
            -- Preserve the entire photo and its aspect ratio within the original
            -- canvas. The unused area is filled with the border color.
            add('-resize', quote(innerWidth .. 'x' .. innerHeight),
                '-background', quote(options.color), '-gravity', 'center',
                '-extent', quote(width .. 'x' .. height))
        end
    end
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
