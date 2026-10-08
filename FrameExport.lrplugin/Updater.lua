local LrTasks = import 'LrTasks'
local LrHttp = import 'LrHttp'
local LrDate = import 'LrDate'
local LrPrefs = import 'LrPrefs'
local LrDigest = import 'LrDigest'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local Core = require 'UpdateCore'
local runtime = require 'Runtime'
local prefs = LrPrefs.prefsForPlugin()
local Updater = {}
local day = 24 * 60 * 60
if prefs.autoCheckUpdates == nil then prefs.autoCheckUpdates = true end
runtime.status = runtime.status or 'Updates have not been checked yet.'
if not runtime.release and prefs.updateManifest then
    local ok, release = LrTasks.pcall(Core.manifest, prefs.updateManifest)
    if ok then runtime.release = release end
end

function Updater.refresh()
    for properties in pairs(runtime.views) do
        properties.updateStatus = runtime.status
        properties.updateVersion = 'Installed version: ' .. runtime.version
        properties.updateCanCheck = not runtime.busy and not runtime.pendingReload
        properties.updateCanInstall = not runtime.busy and not runtime.pendingReload
            and runtime.release ~= nil and Core.newer(runtime.release.version, runtime.version)
        properties.updateBackup = prefs.lastUpdateBackup and ('Backup: ' .. prefs.lastUpdateBackup) or ''
    end
end
runtime.refresh = Updater.refresh

function Updater.bind(properties)
    runtime.views[properties] = true
    Updater.refresh()
end

function Updater.unbind(properties) runtime.views[properties] = nil end

local function status(message)
    runtime.status = message; Updater.refresh()
end

local function get(url, limit)
    local body, headers = LrHttp.get(url, {
        { field = 'User-Agent', value = 'FrameExport/' .. runtime.version },
        { field = 'Content-Type', value = 'skip' },
    }, 30)
    assert(body and headers and headers.status == 200,
        'Download failed (HTTP ' .. tostring(headers and headers.status or 'network error') .. ').')
    assert(#body <= limit, 'Download exceeds the allowed size.')
    return body
end

-- This runs in an async task. A failed check is also throttled so offline
-- machines do not issue repeated requests or show any popup notifications.
function Updater.check(force)
    if runtime.busy or runtime.stopping or runtime.pendingReload then return end
    local now = LrDate.currentTime()
    if not force and type(prefs.lastUpdateCheck) == 'number' and now >= prefs.lastUpdateCheck
        and now - prefs.lastUpdateCheck < day then return end
    runtime.busy = true
    prefs.lastUpdateCheck = now
    status('Checking for updates…')
    local ok, err = LrTasks.pcall(function()
        local body = get(Core.manifestUrl, 8192)
        local release = Core.manifest(body)
        runtime.release = release
        prefs.updateManifest = body
        if Core.newer(release.version, runtime.version) then
            status('Version ' .. release.version .. ' is available. Click Install update when ready.')
        else status('You are up to date.') end
    end)
    runtime.busy = false
    if not ok then status('Could not check for updates: ' .. tostring(err)) else Updater.refresh() end
end

function Updater.checkAsync() LrTasks.startAsyncTask(function() Updater.check(true) end) end

local fs = {
    join = LrPathUtils.child,
    parent = LrPathUtils.parent,
    try = LrTasks.pcall,
    exists = LrFileUtils.exists,
    backupComplete = function(path) prefs.lastUpdateBackup = path end,
    mkdir = function(path)
        local ok, err = LrFileUtils.createAllDirectories(path)
        assert(ok, err or ('Could not create directory: ' .. path))
    end,
    copy = function(source, target)
        local ok, err = LrFileUtils.copy(source, target)
        assert(ok, err or ('Could not copy file: ' .. target))
    end,
    remove = function(path)
        local ok, err = LrFileUtils.delete(path)
        assert(ok, err or ('Could not remove file: ' .. path))
    end,
    write = function(path, data)
        local file, err = io.open(path, 'wb'); assert(file, err)
        local written, writeError = file:write(data)
        local closed, closeError = file:close()
        assert(written and closed, writeError or closeError or ('Could not write file: ' .. path))
    end,
    list = function(root)
        local names = {}
        for path in LrFileUtils.recursiveFiles(root) do
            local relative = path:sub(#root + 2):gsub('\\', '/')
            assert(not relative:match('^%.%.') and relative ~= '', 'Invalid installed plugin path')
            names[#names + 1] = relative
        end
        table.sort(names)
        return names
    end,
}

function Updater.install()
    if runtime.busy or runtime.stopping or runtime.pendingReload or not runtime.release
        or not Core.newer(runtime.release.version, runtime.version) then return end
    local release = runtime.release
    runtime.busy, runtime.installing = true, true
    local staging, backup
    local ok, err = LrTasks.pcall(function()
        while runtime.activeExports > 0 do
            status('Waiting for active exports to finish before installing…')
            LrTasks.sleep(0.5)
            assert(not runtime.stopping, 'Installation canceled because the plugin is shutting down.')
        end
        status('Downloading ' .. release.version .. '…')
        local archive = get(release.url, Core.maxArchiveSize)
        Core.verify(archive, release, LrDigest.SHA256.digest)
        local files = Core.files(archive, release.version)
        assert(not runtime.stopping, 'Installation canceled because the plugin is shutting down.')
        assert(runtime.activeExports == 0, 'An export is still active; no files were changed.')
        local function uniqueDirectory(base)
            local path, index = base, 1
            while LrFileUtils.exists(path) do index = index + 1; path = base .. '-' .. index end
            return path
        end
        staging = uniqueDirectory(_PLUGIN.path .. '.update-staging')
        backup = uniqueDirectory(_PLUGIN.path .. '.backup-v' .. runtime.version)
        status('Installing ' .. release.version .. '…')
        prefs.lastUpdateBackup = Core.install(files, fs, _PLUGIN.path, staging, backup)
        runtime.pendingReload = true
        status('Installed ' .. release.version .. '. Reload the plugin in Plug-in Manager or restart Lightroom before exporting.')
    end)
    LrTasks.pcall(function()
        if staging and LrFileUtils.exists(staging) then LrFileUtils.delete(staging) end
    end)
    runtime.busy, runtime.installing = false, false
    if not ok then
        -- A failed rollback can leave mixed modules. Keep exports blocked until
        -- the user restores the retained backup and reloads the plugin.
        if tostring(err):find('rollback could not finish', 1, true) then
            runtime.pendingReload, runtime.recoveryRequired = true, true
        end
        status('Could not install update: ' .. tostring(err))
    else Updater.refresh() end
end

function Updater.installAsync() LrTasks.startAsyncTask(Updater.install) end

function Updater.start()
    if runtime.started then return end
    runtime.started = true
    if runtime.release then
        status(Core.newer(runtime.release.version, runtime.version)
            and ('Version ' .. runtime.release.version .. ' is available. Click Install update when ready.')
            or 'You are up to date.')
    end
    LrTasks.startAsyncTask(function()
        while not runtime.stopping do
            if prefs.autoCheckUpdates then Updater.check(false) end
            LrTasks.sleep(60)
        end
    end)
end

function Updater.setAutomatic(value) prefs.autoCheckUpdates = value end
function Updater.automatic() return prefs.autoCheckUpdates end
return Updater
