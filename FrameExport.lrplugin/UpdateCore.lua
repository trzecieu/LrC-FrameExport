-- Platform-independent release validation, ZIP reading and installation.
local Core = {}
Core.repository = 'https://github.com/trzecieu/LrC-FrameExport'
Core.manifestUrl = Core.repository .. '/releases/latest/download/FrameExport-update.txt'
Core.maxArchiveSize = 2 * 1024 * 1024

function Core.version(value)
    assert(type(value) == 'string', 'Invalid release version')
    local a, b, c = value:match('^v?(%d+)%.(%d+)%.(%d+)$')
    assert(a and #a <= 6 and #b <= 6 and #c <= 6, 'Invalid release version')
    return { tonumber(a), tonumber(b), tonumber(c) }
end

function Core.newer(candidate, current)
    local a, b = Core.version(candidate), Core.version(current)
    for i = 1, 3 do if a[i] ~= b[i] then return a[i] > b[i] end end
    return false
end

function Core.manifest(body)
    assert(type(body) == 'string' and #body < 8192, 'Invalid update manifest')
    local lines = {}
    for line in body:gmatch('[^\r\n]+') do lines[#lines + 1] = line end
    assert(lines[1] == 'FrameExport update manifest 1', 'Unsupported update manifest')
    local fields = {}
    for i = 2, #lines do
        local key, value = lines[i]:match('^([%a%d]+)=(.+)$')
        assert(key and not fields[key], 'Invalid or duplicate manifest field')
        assert(key == 'version' or key == 'archive' or key == 'sha256', 'Unknown manifest field')
        fields[key] = value
    end
    Core.version(fields.version)
    assert(fields.version:match('^v%d+%.%d+%.%d+$'), 'Invalid release tag')
    assert(fields.archive == 'FrameExport-' .. fields.version .. '.zip', 'Invalid update archive name')
    assert(fields.sha256 and #fields.sha256 == 64 and fields.sha256:match('^%x+$'), 'Invalid SHA-256 checksum')
    fields.sha256 = fields.sha256:lower()
    fields.url = Core.repository .. '/releases/download/' .. fields.version .. '/' .. fields.archive
    return fields
end

function Core.verify(data, release, sha256)
    assert(type(data) == 'string' and #data > 0 and #data <= Core.maxArchiveSize, 'Invalid update archive size')
    assert(sha256(data):lower() == release.sha256, 'SHA-256 verification failed; no files were changed')
end

-- Release ZIPs use ZIP_STORED. Reading them in Lua avoids invoking a shell or
-- relying on platform-specific archive utilities. No archive paths are extracted.
function Core.files(data, expectedVersion)
    assert(type(data) == 'string' and #data <= Core.maxArchiveSize, 'Invalid update archive')
    local function u16(pos)
        local a, b = data:byte(pos, pos + 1)
        assert(b, 'Truncated ZIP')
        return a + b * 256
    end
    local function u32(pos) return u16(pos) + u16(pos + 2) * 65536 end
    local ending
    for pos = #data - 21, math.max(1, #data - 65557), -1 do
        if data:sub(pos, pos + 3) == 'PK\005\006' and pos + 21 + u16(pos + 20) == #data then
            ending = pos; break
        end
    end
    assert(ending and u16(ending + 4) == 0 and u16(ending + 6) == 0, 'Unsupported ZIP layout')
    local count, central = u16(ending + 10), u32(ending + 16) + 1
    assert(count > 0 and count <= 128 and count == u16(ending + 8), 'Invalid ZIP entry count')
    assert(central + u32(ending + 12) == ending, 'Invalid ZIP directory bounds')
    local position, files, seen = central, {}, {}
    for _ = 1, count do
        assert(data:sub(position, position + 3) == 'PK\001\002', 'Invalid ZIP directory')
        local flags, method = u16(position + 8), u16(position + 10)
        local size, unpacked = u32(position + 20), u32(position + 24)
        local nameSize, extraSize, commentSize = u16(position + 28), u16(position + 30), u16(position + 32)
        local name = data:sub(position + 46, position + 45 + nameSize)
        assert(#name == nameSize and not seen[name], 'Duplicate or truncated ZIP filename')
        seen[name] = true
        assert((flags == 0 or flags == 2048) and method == 0 and size == unpacked,
            'Update archive must use unencrypted ZIP_STORED entries')
        local mode = math.floor(u32(position + 38) / 65536 / 4096) % 16
        assert(mode == 0 or mode == 8, 'ZIP links and special files are not allowed')
        local relative = name:match('^FrameExport%.lrplugin/([%w_-]+%.lua)$')
        assert(relative or name == 'README.md', 'Unexpected path in update archive')
        local localPos = u32(position + 42) + 1
        assert(localPos >= 1 and data:sub(localPos, localPos + 3) == 'PK\003\004', 'Invalid ZIP entry')
        local localNameSize, localExtraSize = u16(localPos + 26), u16(localPos + 28)
        assert(u16(localPos + 6) == flags and u16(localPos + 8) == method
            and u32(localPos + 18) == size and u32(localPos + 22) == size,
            'Inconsistent ZIP entry headers')
        assert(data:sub(localPos + 30, localPos + 29 + localNameSize) == name, 'ZIP filename mismatch')
        local contentPos = localPos + 30 + localNameSize + localExtraSize
        assert(contentPos + size <= central, 'Invalid ZIP data bounds')
        if relative then files[relative] = data:sub(contentPos, contentPos + size - 1) end
        position = position + 46 + nameSize + extraSize + commentSize
    end
    assert(position == ending, 'Invalid ZIP directory length')
    for _, name in ipairs({ 'Info.lua', 'Frame.lua', 'Magick.lua', 'ExportFilter.lua',
        'Runtime.lua', 'Updater.lua', 'UpdateCore.lua', 'PluginInfo.lua', 'Init.lua', 'Shutdown.lua' }) do
        assert(files[name] and #files[name] > 0, 'Update is missing ' .. name)
    end
    local info = files['Info.lua']
    local a, b, c = info:match('VERSION%s*=%s*{%s*major%s*=%s*(%d+)%s*,%s*minor%s*=%s*(%d+)%s*,%s*revision%s*=%s*(%d+)')
    assert(a and 'v' .. a .. '.' .. b .. '.' .. c == expectedVersion, 'Archive version does not match release')
    assert(info:match("LrToolkitIdentifier%s*=%s*['\"]pl%.trzecieu%.frameexport['\"]"), 'Wrong plugin identity')
    return files
end

-- fs is an SDK adapter (or a test double). Stage and back up before touching
-- installed files. Preserve unrelated local files and retain the backup on success.
function Core.install(files, fs, plugin, staging, backup)
    local names = {}
    for name in pairs(files) do
        assert(name:match('^[%w_-]+%.lua$'), 'Invalid plugin filename')
        names[#names + 1] = name
    end
    table.sort(names)
    fs.mkdir(staging)
    fs.mkdir(backup)
    for _, name in ipairs(names) do fs.write(fs.join(staging, name), files[name]) end
    for _, name in ipairs(fs.list(plugin)) do
        fs.mkdir(fs.parent(fs.join(backup, name)))
        fs.copy(fs.join(plugin, name), fs.join(backup, name))
    end
    if fs.backupComplete then fs.backupComplete(backup) end
    local touched = {}
    local ok, err = fs.try(function()
        for _, name in ipairs(names) do
            local target = fs.join(plugin, name)
            touched[#touched + 1] = name
            if fs.exists(target) then fs.remove(target) end
            fs.copy(fs.join(staging, name), target)
        end
    end)
    if not ok then
        local restored, restoreError = fs.try(function()
            for _, name in ipairs(touched) do
                local target, saved = fs.join(plugin, name), fs.join(backup, name)
                if fs.exists(target) then fs.remove(target) end
                if fs.exists(saved) then fs.copy(saved, target) end
            end
        end)
        if not restored then
            error('Update failed and rollback could not finish: ' .. tostring(restoreError)
                .. '. The backup is at: ' .. backup)
        end
        error('Update failed; the previous version was restored: ' .. tostring(err))
    end
    return backup
end

return Core
