-- Real release ZIPs, disk writes, SHA-256 and failures with a mocked Adobe SDK.
local root = assert(arg[1], 'Fixture directory required')
local source = 'FrameExport.lrplugin'
package.path = source .. '/?.lua;' .. package.path
_PLUGIN = { path = root .. '/installed/FrameExport.lrplugin' }
local Frame = dofile(source .. '/Frame.lua')
local q = function(path) return Frame.quote(path, false) end
local count = 0
local function check(value, message) assert(value, message); count = count + 1 end
local function read(path)
    local file = io.open(path, 'rb'); if not file then return nil end
    local contents = file:read('*a'); file:close(); return contents
end
local function write(path, data)
    local file = assert(io.open(path, 'wb')); assert(file:write(data)); assert(file:close())
end
local function execute(command)
    local ok, _, code = os.execute(command)
    if type(ok) == 'number' then return ok end
    return ok and 0 or (code or 1)
end
local function hash(data)
    write(root .. '/hash-input', data)
    assert(execute('sha256sum ' .. q(root .. '/hash-input') .. ' > ' .. q(root .. '/hash-result')) == 0)
    return assert(read(root .. '/hash-result'):match('^%x+'))
end
local now, calls, queue, prefs = 100000, {}, {}, {}
local body, httpStatus, onSleep, onGet
local failCopy, failBackup, failRollback = false, false, false
local files = {
    exists = function(path)
        if execute('test -d ' .. q(path)) == 0 then return 'directory' end
        if read(path) then return 'file' end
    end,
    createAllDirectories = function(path) return execute('mkdir -p ' .. q(path)) == 0 end,
    copy = function(from, to)
        if failCopy and to == _PLUGIN.path .. '/Info.lua' then
            failCopy = false; return false, 'injected replacement failure'
        end
        if failBackup and to:find('.backup-', 1, true) then return false, 'injected backup failure' end
        if failRollback and from:find('.backup-', 1, true) and to == _PLUGIN.path .. '/Info.lua' then
            return false, 'injected rollback failure'
        end
        return execute('cp ' .. q(from) .. ' ' .. q(to)) == 0
    end,
    delete = function(path) return execute('rm -rf ' .. q(path)) == 0 end,
    recursiveFiles = function(path)
        assert(execute('find ' .. q(path) .. ' -type f > ' .. q(root .. '/file-list')) == 0)
        local list = {}
        for entry in read(root .. '/file-list'):gmatch('[^\n]+') do list[#list + 1] = entry end
        local i = 0; return function() i = i + 1; return list[i] end
    end,
}
local imports = {
    LrTasks = {
        pcall = pcall,
        startAsyncTask = function(fn) queue[#queue + 1] = fn end,
        sleep = function(seconds) if onSleep then onSleep(seconds) end end,
    },
    LrHttp = { get = function(url, headers)
        calls[#calls + 1] = url
        check(headers[1].field == 'User-Agent', 'HTTP requests identify the plugin')
        if onGet then onGet(url) end
        return body, { status = httpStatus }
    end },
    LrDate = { currentTime = function() return now end },
    LrPrefs = { prefsForPlugin = function() return prefs end },
    LrDigest = { SHA256 = { digest = hash } },
    LrFileUtils = files,
    LrPathUtils = { child = function(a, b) return a .. '/' .. b end,
        parent = function(path) return assert(path:match('^(.*)/[^/]+$')) end },
    LrView = { bind = function(key) return key end },
}
-- LrDialogs is intentionally unavailable: no update path may show a popup.
function import(name) return assert(imports[name], 'Unexpected SDK import: ' .. name) end
local Core, runtime = require 'UpdateCore', require 'Runtime'
local Updater = require 'Updater'
local archive = assert(read(root .. '/assets/FrameExport-v1.0.1.zip'))
local manifest = assert(read(root .. '/assets/FrameExport-update.txt'))
local release = Core.manifest(manifest)
check(Core.newer('1.10.0', '1.9.9'), 'Numeric semantic version comparison')
check(not Core.newer('1.0.0', '1.0.0') and not Core.newer('0.9.9', '1.0.0'), 'No reinstall or downgrade')
for _, value in ipairs({ 'v1.0.0-beta', '1.0', '../v1.0.1', '9999999999.0.0' }) do
    check(not pcall(Core.version, value), 'Malformed version rejected')
end
for _, value in ipairs({ manifest .. 'version=v1.0.1\n', manifest:gsub('archive=', 'url='),
    manifest:gsub('FrameExport%-v1.0.1.zip', '../other.zip'), manifest:gsub('sha256=%x+', 'sha256=bad') }) do
    check(not pcall(Core.manifest, value), 'Malformed manifest rejected')
end
Core.verify(archive, release, hash)
check(not pcall(Core.verify, archive .. 'tampered', release, hash), 'Real SHA-256 detects tampering')
local payload = Core.files(archive, release.version)
check(payload['Updater.lua'] and payload['Info.lua']:find('revision = 1', 1, true), 'Real package parsed')
for _, case in ipairs({ 'compressed', 'traversal', 'missing', 'duplicate', 'symlink', 'wrong-version' }) do
    check(not pcall(Core.files, assert(read(root .. '/' .. case .. '.zip')), release.version), 'ZIP rejected: ' .. case)
end
check(not pcall(Core.files, archive:sub(1, -10), release.version), 'Truncated ZIP rejected')
check(not pcall(Core.files, archive:gsub('PK\003\004', 'BAD!', 1), release.version), 'Broken local header rejected')

local properties = {}
Updater.bind(properties)
check(properties.updateVersion == 'Installed version: 1.0.0', 'UI reports loaded version')
body, httpStatus = manifest, 200
Updater.check(false)
check(#calls == 1 and properties.updateCanInstall, 'First automatic check discovers newer release')
check(calls[1] == Core.manifestUrl and release.url:find('trzecieu/LrC%-FrameExport'), 'New repository URLs used')
Updater.check(false)
check(#calls == 1, 'Automatic checks throttled to once a day')
now = now + 86400; Updater.check(false)
check(#calls == 2, 'Automatic checks repeat after a day')
Updater.check(true)
check(#calls == 3, 'Manual check bypasses daily throttle')
runtime.busy = true; Updater.check(true); runtime.busy = false
check(#calls == 3, 'Concurrent check suppressed')
body, httpStatus = nil, 429; Updater.check(true)
check(properties.updateStatus:find('HTTP 429', 1, true), 'HTTP error shown only in status')
local failedCalls = #calls; Updater.check(false)
check(#calls == failedCalls, 'Failed checks are also throttled')

local oldInfo = read(_PLUGIN.path .. '/Info.lua')
local oldFiles = {}
for path in files.recursiveFiles(_PLUGIN.path) do oldFiles[path] = read(path) end
body, httpStatus = archive .. 'tampered', 200
Updater.install()
check(read(_PLUGIN.path .. '/Info.lua') == oldInfo and not runtime.pendingReload, 'Checksum failure leaves installation unchanged')
check(not runtime.installing and not runtime.busy, 'Locks released after failed verification')
body, httpStatus = archive, 200
failBackup = true; Updater.install(); failBackup = false
check(read(_PLUGIN.path .. '/Info.lua') == oldInfo, 'Backup failure never modifies installed files')
failCopy = true; Updater.install()
check(read(_PLUGIN.path .. '/Info.lua') == oldInfo and not runtime.pendingReload, 'Replacement failure restores prior version')
check(properties.updateStatus:find('previous version was restored', 1, true), 'Rollback reported')
for path, contents in pairs(oldFiles) do
    check(read(path) == contents, 'Rollback restores all previously modified files')
end
failCopy, failRollback = true, true; Updater.install(); failRollback = false
check(runtime.pendingReload and runtime.recoveryRequired, 'Failed rollback blocks exports until backup restoration')
check(properties.updateStatus:find('rollback could not finish', 1, true), 'Failed rollback identifies recovery requirement')
check(properties.updateBackup:find(prefs.lastUpdateBackup, 1, true)
    and read(prefs.lastUpdateBackup .. '/Info.lua') == oldInfo, 'Failed rollback points to the complete recovery backup')
for path, contents in pairs(oldFiles) do write(path, contents) end
runtime.pendingReload, runtime.recoveryRequired = false, false

onGet = function() runtime.activeExports = 1 end
Updater.install(); onGet = nil
check(read(_PLUGIN.path .. '/Info.lua') == oldInfo, 'No files change if an export appears during download')
check(not runtime.installing and not runtime.busy, 'Late export guard releases update locks')
runtime.activeExports = 0

local extra = _PLUGIN.path .. '/custom/settings.txt'
assert(files.createAllDirectories(_PLUGIN.path .. '/custom')); write(extra, 'preserve me')
runtime.activeExports = 1
onSleep = function(seconds)
    check(seconds == 0.5 and runtime.installing and runtime.busy, 'Installation waits while exports are locked')
    runtime.activeExports = 0
end
Updater.install(); onSleep = nil
check(runtime.pendingReload and read(_PLUGIN.path .. '/Info.lua') == payload['Info.lua'], 'Successful update installs correct version and requires reload')
check(not properties.updateCanInstall and not properties.updateCanCheck, 'Actions disabled until reload')
check(prefs.lastUpdateBackup and read(prefs.lastUpdateBackup .. '/Info.lua') == oldInfo, 'Prior version retained in backup')
check(read(extra) == 'preserve me' and read(prefs.lastUpdateBackup .. '/custom/settings.txt') == 'preserve me', 'Local files retained and backed up')
for name, data in pairs(payload) do
    check(read(_PLUGIN.path .. '/' .. name) == data, 'Installed content matches ZIP: ' .. name)
end
local pendingCalls = #calls; Updater.check(true); Updater.install()
check(#calls == pendingCalls, 'Reload requirement prevents repeated network and install actions')

-- Emulate a Lightroom reload: cached checks and prefs survive, loaded code does not.
package.loaded.Runtime, package.loaded.Updater = nil, nil
runtime, Updater = require 'Runtime', require 'Updater'
check(runtime.version == '1.0.1' and not runtime.pendingReload, 'Reload activates installed version')
body, httpStatus = manifest, 200
local checksBeforeStartup = #calls
onSleep = function(seconds) check(seconds == 60, 'Background task sleeps between checks'); runtime.stopping = true end
Updater.start(); Updater.start()
check(#queue == 1, 'Only one background task starts')
table.remove(queue, 1)(); onSleep = nil; runtime.stopping = false
check(#calls == checksBeforeStartup, 'Daily throttle survives reload')
check(runtime.status == 'You are up to date.', 'Cached release reconciled with newly loaded version')
Updater.setAutomatic(false)
check(not Updater.automatic(), 'Automatic checking can be disabled')

local PluginInfo = dofile(source .. '/PluginInfo.lua')
local observed
function properties:removeObserver() observed = nil end
function properties:addObserver(key, owner, callback) observed = function(value) callback(owner, self, key, value) end end
PluginInfo.startDialog(properties)
observed(true); check(Updater.automatic(), 'Manager checkbox persists preference')
local factory = { control_spacing = function() return 6 end }
for _, kind in ipairs({ 'column', 'row', 'static_text', 'checkbox', 'push_button' }) do
    factory[kind] = function(_, props) props.kind = kind; return props end
end
local sections = PluginInfo.sectionsForTopOfDialog(factory, properties)
local buttons = {}
local function visit(node)
    if type(node) ~= 'table' then return end
    if node.kind == 'push_button' then buttons[node.title] = node end
    for _, child in ipairs(node) do visit(child) end
end
visit(sections)
check(buttons['Install update'] and buttons['Check for updates'], 'Manager exposes required controls')
check(not properties.updateCanInstall, 'Install button disabled when up to date')
PluginInfo.endDialog(properties); check(not observed, 'Manager observer cleaned up')
check(not runtime.views[properties], 'Closed manager view detached from background task')
Updater.bind(properties)
body, httpStatus = nil, 404
Updater.checkAsync(); table.remove(queue, 1)()
check(properties.updateStatus:find('HTTP 404', 1, true), 'Missing manifest does not pop up or prevent exporting')
print('PASS: ' .. count .. ' updater checks (real ZIP, disk transactions and SHA-256; Adobe SDK mocked)')
