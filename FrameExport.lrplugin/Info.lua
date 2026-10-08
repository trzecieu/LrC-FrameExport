return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'pl.trzecieu.frameexport',
    LrPluginName = 'FrameExport',
    VERSION = { major = 1, minor = 2, revision = 0, build = 4 },
    LrInitPlugin = 'Init.lua',
    LrShutdownPlugin = 'Shutdown.lua',
    LrPluginInfoProvider = 'PluginInfo.lua',
    LrExportFilterProvider = {
        title = 'FrameExport',
        file = 'ExportFilter.lua',
        id = 'frameexport',
    },
}
