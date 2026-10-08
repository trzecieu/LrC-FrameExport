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
        extension = function(path) return path:match('%.([^%.]+)$') end },
    LrView = { bind = function(key) return key end },
}
function import(name) return assert(imports[name], name) end
_PLUGIN = { path = 'FrameExport.lrplugin' }
WIN_ENV = false
local provider = dofile('FrameExport.lrplugin/ExportFilter.lua')
local function run(path, overrides, sourceSuccess)
    local properties = { frameWidthPercent = 10, frameHeightPercent = 20,
        frameColor = '#00FF00', frameMagick = '/usr/bin/magick',
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
check(w == 111 and h == 97, 'Percentage rounding on TIFF')
check(capture('magick ' .. q(path) .. " -format '%[hex:p{0,0}]' info:"):match('^0000FFFF0000'), 'Border color and 16-bit TIFF')
check(capture('magick ' .. q(path) .. " -format '%[hex:p{5,8}]' info:"):match('^FFFF00000000'), 'Source pixels preserved')

path = root .. '/photo.jpg'; create(path, '1000x800')
result = run(path, { LR_format = 'JPEG' })
check(result.ok, result.err)
w, h = dimensions(path)
check(w == 1100 and h == 960, 'JPEG dimensions')
local original = read(path)
result = run(path, { frameWidthPercent = 0, frameHeightPercent = 0 })
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
    check(not Frame.validate(bad, 10, '#FFFFFF', '/usr/bin/magick'), 'Invalid percentage')
end
local options = assert(Frame.validate(10.5, 0, '#abcdef', 'C:\\Program Files\\magick.exe'))
options.pixelWidth, options.pixelHeight = 1000, 800
local command = Frame.command(options, 'C:\\photos\\in.jpg', 'C:\\photos\\out.jpg',
    'C:\\photos\\log.txt', true, 'JPEG', 0.85)
check(command:find('"53x0"', 1, true) and command:find('-quality 85', 1, true), 'Windows command and rounding')
check(not pcall(Frame.quote, 'C:\\photos\\%TEMP%.jpg', true), 'Windows expansion refused')
check(not pcall(Frame.quote, 'bad\npath', false), 'Newline refused')
check(execute('find ' .. q(root) .. " -name '*.frame*' | rg . > /dev/null") ~= 0, 'No temporary files remain')
assert(execute('rm -r ' .. q(root)) == 0)
print('PASS: ' .. tests .. ' checks (real ImageMagick; Lightroom SDK mocked)')
