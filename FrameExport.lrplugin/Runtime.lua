-- require() shares this state across the export filter, startup and manager UI.
local info = dofile(_PLUGIN.path .. '/Info.lua')
return {
    version = string.format('%d.%d.%d', info.VERSION.major, info.VERSION.minor, info.VERSION.revision),
    activeExports = 0,
    installing = false,
    pendingReload = false,
    stopping = false,
    busy = false,
    views = setmetatable({}, { __mode = 'k' }),
}
