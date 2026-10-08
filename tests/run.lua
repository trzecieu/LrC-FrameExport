-- Run from the repository root: luatex --luaonly tests/run.lua
local Frame = dofile('FrameExport.lrplugin/Frame.lua')
local q = function(v) return Frame.quote(v, false) end
local root = os.tmpname()
os.remove(root)
assert(os.execute('mkdir -p ' .. q(root)))
local tests = 0
local function check(value, message)
    assert(value, message)
    tests = tests + 1
end
local function read(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a'); f:close(); return data
end
local function execute(command)
    local ok, _, status = os.execute(command)
    if type(ok) == 'number' then return ok end
    return ok and 0 or (status or 1)
end
local function capture(command)
    local result = root .. '/result.txt'
    assert(execute(command .. ' > ' .. q(result)) == 0)
    return read(result)
end
local failInstall = false
local files = {
    exists = function(path) return read(path) and 'file' or nil end,
    readFile = read,
    chooseUniqueFileName = function(path)
        local candidate, index = path, 0
        while read(candidate) do index = index + 1; candidate = path .. tostring(index) end
        return candidate
    end,
    delete = os.remove,
    move = function(source, destination)
        if failInstall and source:match('%.frame%.tif$') then
            return false, 'simulated installation failure'
        end
        return os.rename(source, destination)
    end,
}
local imports = {
    LrTasks = { execute = execute, pcall = pcall },
    LrFileUtils = files,
    LrPathUtils = { child = function(a, b) return a .. '/' .. b end,
        isAbsolute = function(path) return path:sub(1, 1) == '/' or path:match('^%a:[/\\]') ~= nil end,
        getStandardFilePath = function(which) assert(which == 'temp'); return root end,
        leafName = function(path) return path:match('[^/\\]+$') end,
        extension = function(path) return path:match('%.([^%.]+)$') end },
    LrView = { bind = function(key) return key end },
    LrColor = function(r, g, b) return {
        red = function() return r end, green = function() return g end, blue = function() return b end,
    } end,
    LrDialogs = { runOpenPanel = function() return nil end },
}
imports.LrTasks.startAsyncTask = function(task) task() end
function import(name) return assert(imports[name], name) end
_PLUGIN = { path = 'FrameExport.lrplugin' }
WIN_ENV = false
local provider = dofile('FrameExport.lrplugin/ExportFilter.lua')
local function run(path, overrides, sourceSuccess)
    local properties = { frameWidthPercent = 10,
        frameColor = '#00FF00', frameMagick = '',
        LR_format = 'TIFF', LR_jpeg_quality = 0.9 }
    for key, value in pairs(overrides or {}) do properties[key] = value end
    local outcome = {}
    local source = { waitForRender = function() return sourceSuccess ~= false, path end }
    local target = { renditionIsDone = function(_, ok, err)
        outcome.ok, outcome.err = ok, err; outcome.calls = (outcome.calls or 0) + 1
    end }
    provider.postProcessRenderedPhotos({}, { propertyTable = properties,
        renditions = function() local done = false; return function()
            if done then return end
            done = true; return source, target
        end end })
    check(outcome.calls == 1, 'Rendition must complete exactly once')
    return outcome
end
local function create(path, geometry)
    assert(execute('magick -size ' .. geometry .. ' xc:red -depth 16 ' .. q(path)) == 0)
end
local function dimensions(path)
    return Frame.dimensions(capture('magick identify -ping -verbose ' .. q(path)))
end
local path = root .. "/photo with 'quote $ and spaces.tif"
create(path, '101x81')
local result = run(path)
check(result.ok, result.err)
local w, h = dimensions(path)
check(w == 111 and h == 91, 'Equal border width on rectangular TIFF')
check(capture('magick ' .. q(path) .. " -format '%[hex:p{0,0}]' info:"):match('^0000FFFF0000'), 'Border color and 16-bit TIFF')
check(capture('magick ' .. q(path) .. " -format '%[hex:p{5,5}]' info:"):match('^FFFF00000000'), 'Source pixels preserved')
check(capture('magick ' .. q(path) .. " -format '%[hex:p{4,40}] %[hex:p{50,4}] %[hex:p{106,40}] %[hex:p{50,86}]' info:") ==
    '0000FFFF0000 0000FFFF0000 0000FFFF0000 0000FFFF0000', 'All four border edges have the same thickness')

path = root .. '/portrait.tif'; create(path, '80x160')
result = run(path)
check(result.ok, result.err)
w, h = dimensions(path)
check(w == 88 and h == 168, 'Equal border width on portrait image')
check(capture('magick ' .. q(path) .. " -format '%[hex:p{4,4}]' info:"):match('^FFFF00000000'), 'Portrait source starts at equal x/y offset')

path = root .. '/photo.jpg'; create(path, '1000x800')
result = run(path, { LR_format = 'JPEG' })
check(result.ok, result.err)
w, h = dimensions(path)
check(w == 1100 and h == 900, 'Equal JPEG border dimensions')
local original = read(path)
result = run(path, { frameWidthPercent = 0, frameMagick = '/missing/magick' })
check(result.ok and read(path) == original, 'Zero border leaves bytes untouched')
result = run(path, { frameMagick = '/missing/magick' })
check(not result.ok and read(path) == original, 'Missing executable preserves original')
result = run(path, { frameMagick = '/usr/bin/false' })
check(not result.ok and read(path) == original, 'Process failure preserves original')
result = run(path, { frameColor = 'red; echo injected' })
check(not result.ok and read(path) == original, 'Invalid color refused')
result = run(path, { LR_format = 'PSD' })
check(not result.ok and read(path) == original, 'Unsupported format refused')
result = run('render failed', {}, false)
check(not result.ok and result.err == 'render failed', 'Upstream failure propagated')

path = root .. '/rollback.tif'; create(path, '100x80'); original = read(path)
failInstall = true; result = run(path); failInstall = false
check(not result.ok and read(path) == original, 'Failed replacement rolls back')
for _, bad in ipairs({ -1, 201, 'abc' }) do
    check(not Frame.validate(bad, '#FFFFFF', '/usr/bin/magick'), 'Invalid percentage')
end
local options = assert(Frame.validate(10.5, '#abcdef', 'C:\\Program Files\\magick.exe'))
options.pixelWidth, options.pixelHeight = 1000, 800
local command = Frame.command(options, 'C:\\photos\\in.jpg', 'C:\\photos\\out.jpg',
    'C:\\photos\\log.txt', true, 'JPEG', 0.85)
check(command:find('"53x53"', 1, true) and command:find('-quality 85', 1, true), 'Windows command and equal rounding')
check(not pcall(Frame.quote, 'C:\\photos\\%TEMP%.jpg', true), 'Windows expansion refused')
check(not pcall(Frame.quote, 'bad\npath', false), 'Newline refused')

local Magick = dofile('FrameExport.lrplugin/Magick.lua')
check(Magick.find('', false):match('/magick$'), 'Real PATH discovery')
local custom = root .. "/custom ' magick"
assert(execute('ln -s /usr/bin/magick ' .. q(custom)) == 0)
check(Magick.find(custom, false) == custom, 'Manual override with spaces and quote')
local broken = root .. '/broken-magick'
local wrapper = assert(io.open(broken, 'w'))
wrapper:write('#!/bin/sh\nif [ "$1" = "-version" ]; then exec /usr/bin/magick -version; fi\nexit 1\n')
wrapper:close()
assert(execute('chmod +x ' .. q(broken)) == 0)
original = read(path)
result = run(path, { frameMagick = broken })
check(not result.ok and read(path) == original, 'Processing failure after successful version probe preserves export')

-- Mock the OS for Windows/macOS discovery; actual Windows execution remains
-- a desktop integration check, not a claim made by these tests.
local savedExecute, savedExists = imports.LrTasks.execute, files.exists
local simulatedFiles, simulatedReport, visited = {}, '', {}
files.exists = function(candidate)
    if candidate == root .. '/frameexport-discovery.txt' then return nil end
    return simulatedFiles[candidate]
end
local savedRead = files.readFile
files.readFile = function() return simulatedReport end
local programFiles = 'D:\\Program Files'
local installedFolder = programFiles .. '/ImageMagick-7.1.2-Q16'
files.directoryEntries = function(folder)
    check(folder == programFiles, 'Windows installation folder from environment')
    local i = 0
    local entries = { folder .. '/Unrelated', installedFolder }
    return function() i = i + 1; return entries[i] end
end
imports.LrTasks.execute = function(cmd)
    visited[#visited + 1] = cmd
    if cmd:match('^where.exe') then
        simulatedReport = 'D:\\old\\magick.exe\r\nD:\\new\\magick.exe\r\n'
        return 0
    elseif cmd:match('^command %-v') then
        simulatedReport = 'not found'; return 1
    elseif cmd:match('^echo %%ProgramFiles%%') then
        simulatedReport = programFiles .. '\r\n'; return 0
    elseif cmd:match('^echo %%ProgramFiles%(x86%)%%') then
        simulatedReport = '%ProgramFiles(x86)%\r\n'; return 0
    elseif cmd:find('D:\\old\\magick.exe', 1, true) then
        simulatedReport = 'Version: ImageMagick 6.9'; return 0
    elseif cmd:find('-version', 1, true) then
        simulatedReport = 'Version: ImageMagick 7.1.2'; return 0
    end
    simulatedReport = ''; return 1
end
simulatedFiles['D:\\old\\magick.exe'], simulatedFiles['D:\\new\\magick.exe'] = 'file', 'file'
check(Magick.find('', true) == 'D:\\new\\magick.exe', 'Windows PATH skips unsuitable version')
simulatedFiles = { [programFiles] = 'directory', [installedFolder .. '/magick.exe'] = 'file' }
check(Magick.find('', true) == installedFolder .. '/magick.exe', 'Windows installation fallback outside C drive')
simulatedFiles = { ['/opt/homebrew/bin/magick'] = 'file' }
check(Magick.find('', false) == '/opt/homebrew/bin/magick', 'Homebrew fallback when GUI PATH lacks magick')
simulatedFiles = {}
check(not pcall(Magick.find, '', false), 'No installation produces a clear failure')
files.exists, files.readFile, imports.LrTasks.execute = savedExists, savedRead, savedExecute

local factory = {}
for _, kind in ipairs({ 'column', 'row', 'static_text', 'edit_field', 'color_well', 'push_button' }) do
    factory[kind] = function(_, props) props.kind = kind; return props end
end
factory.control_spacing = function() return 6 end
local props = { frameMagick = '', frameWidthPercent = 10, frameColor = '#1A80FF' }
local section = provider.sectionForFilterInDialog(factory, props)
check(props.frameMagickStatus:match('Found:'), 'Dialog automatically starts discovery')
local swatch, hexField, pickerButton, detectButton
local function visit(node)
    if type(node) ~= 'table' then return end
    if node.kind == 'color_well' then swatch = node end
    if node.kind == 'edit_field' and node.value == 'frameColor' then hexField = node end
    if node.kind == 'push_button' and node.title == 'Choose…' then pickerButton = node end
    if node.kind == 'push_button' and node.title == 'Detect again' then detectButton = node end
    for _, child in ipairs(node) do visit(child) end
end
visit(section)
check(swatch and hexField and swatch.value.key == hexField.value, 'Color picker and HEX bind to same preset property')
local color = swatch.value.transform(props.frameColor, true)
check(color:red() == 26 / 255 and color:green() == 128 / 255 and color:blue() == 1, 'HEX updates picker')
check(swatch.value.transform(imports.LrColor(1, 0.5, 0), false) == '#FF8000', 'Picker updates HEX')
check(swatch.value.transform('#ABCDEF', true):red() == 171 / 255, 'Preset color populates picker')
check(Frame.rgbToHex(-1, 2, 0) == '#00FF00', 'RGB conversion clamps channel range')
imports.LrDialogs.runOpenPanel = function() return { custom } end
pickerButton.action()
check(props.frameMagick == custom and props.frameMagickStatus:find(custom, 1, true), 'File picker sets and validates custom executable')
imports.LrDialogs.runOpenPanel = function() return nil end
pickerButton.action()
check(props.frameMagick == custom, 'Cancel executable picker preserves setting')
detectButton.action()
check(props.frameMagick == '' and props.frameMagickStatus:match('Found:'), 'Reset restores automatic detection')
check(execute('find ' .. q(root) .. " -name '*.frame*' | rg . > /dev/null") ~= 0, 'No temporary files remain')
assert(execute('rm -r ' .. q(root)) == 0)
print('PASS: ' .. tests .. ' checks (real ImageMagick; Lightroom SDK mocked)')
