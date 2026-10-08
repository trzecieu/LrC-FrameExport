local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrView = import 'LrView'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local Frame = dofile(LrPathUtils.child(_PLUGIN.path, 'Frame.lua'))
local Magick = dofile(LrPathUtils.child(_PLUGIN.path, 'Magick.lua'))
local provider = {}

provider.exportPresetFields = {
    { key = 'frameWidthPercent', default = 10 },
    { key = 'frameColor', default = '#FFFFFF' },
    { key = 'frameMagick', default = '' },
}

function provider.sectionForFilterInDialog(f, properties)
    local bind = LrView.bind
    local function detect()
        local manual = properties.frameMagick
        properties.frameMagickStatus = 'Szukam ImageMagick 7…'
        LrTasks.startAsyncTask(function()
            local ok, path = LrTasks.pcall(Magick.find, manual, WIN_ENV)
            if properties.frameMagick == manual then
                properties.frameMagickStatus = ok and ('Znaleziono: ' .. path) or tostring(path)
            end
        end)
    end
    detect()
    return {
        title = 'Ramka przy eksporcie',
        f:column {
            bind_to_object = properties,
            spacing = f:control_spacing(),
            f:static_text { title = 'Jednakowa grubość ramki w pikselach na wszystkich czterech krawędziach.' },
            f:row {
                f:static_text { title = 'Przyrost szerokości (%)', width = 165 },
                f:edit_field { value = bind 'frameWidthPercent', width_in_chars = 8 },
            },
            f:row {
                f:static_text { title = 'Kolor ramki', width = 165 },
                f:color_well {
                    value = bind {
                        key = 'frameColor',
                        transform = function(value, fromModel)
                            if fromModel then
                                local r, g, b = Frame.hexToRgb(value)
                                return LrColor(r or 1, g or 1, b or 1)
                            end
                            return Frame.rgbToHex(value:red(), value:green(), value:blue())
                        end,
                    },
                },
                f:edit_field { value = bind 'frameColor', width_in_chars = 12 },
            },
            f:row {
                f:static_text { title = 'Ścieżka (opcjonalna)', width = 165 },
                f:edit_field { value = bind 'frameMagick', width_in_chars = 35 },
                f:push_button { title = 'Wybierz…', action = function()
                    local paths = LrDialogs.runOpenPanel {
                        title = 'Wybierz program ImageMagick 7 (magick)',
                        canChooseFiles = true, canChooseDirectories = false,
                        allowsMultipleSelection = false,
                    }
                    if paths and paths[1] then properties.frameMagick = paths[1]; detect() end
                end },
            },
            f:row {
                f:push_button { title = 'Wykryj ponownie', action = function()
                    properties.frameMagick = ''; detect()
                end },
                f:static_text { title = 'Puste pole = szukanie w PATH i typowych folderach instalacji.' },
            },
            f:static_text { title = bind 'frameMagickStatus', width_in_chars = 60, height_in_lines = -1 },
            f:static_text { title = 'ImageMagick 7 • JPEG / TIFF • ramka po skalowaniu i znaku wodnym' },
            f:static_text { title = '10% dodaje na każdej krawędzi 5% szerokości zdjęcia — również u góry i u dołu.' },
        },
    }
end

local function process(options, path, settings)
    if options.width == 0 then return end
    assert(settings.LR_format == 'JPEG' or settings.LR_format == 'TIFF',
        'Ramka obsługuje wyłącznie eksport JPEG i TIFF. Wybierz jeden z tych formatów.')
    assert(LrFileUtils.exists(options.executable) == 'file',
        'Nie znaleziono programu magick. Zainstaluj ImageMagick 7 i podaj pełną ścieżkę.')
    -- Keep the suffix: ImageMagick chooses the output encoder from it.
    local suffix = LrPathUtils.extension(path)
    local temporary = LrFileUtils.chooseUniqueFileName(path .. '.frame.' .. suffix)
    local backup = LrFileUtils.chooseUniqueFileName(path .. '.frame-original')
    local log = LrFileUtils.chooseUniqueFileName(path .. '.frame.log')
    local ok, err = LrTasks.pcall(function()
        local identified = LrTasks.execute(Frame.identifyCommand(options.executable, path, log, WIN_ENV))
        assert(identified == 0, 'ImageMagick nie może odczytać eksportu: ' ..
            (LrFileUtils.readFile(log) or ''):sub(1, 2000))
        options.pixelWidth, options.pixelHeight = Frame.dimensions(LrFileUtils.readFile(log) or '')
        local command = Frame.command(options, path, temporary, log, WIN_ENV,
            settings.LR_format, settings.LR_jpeg_quality)
        local status = LrTasks.execute(command)
        if status ~= 0 or LrFileUtils.exists(temporary) ~= 'file' then
            local details = LrFileUtils.readFile(log) or ''
            error('ImageMagick: kod ' .. tostring(status) .. '. ' .. details:sub(1, 2000))
        end
        local moved, reason = LrFileUtils.move(path, backup)
        assert(moved, reason or 'Nie można zabezpieczyć pliku przed podmianą.')
        local installed, installError = LrFileUtils.move(temporary, path)
        if not installed then
            local restored, restoreError = LrFileUtils.move(backup, path)
            if not restored then
                error('Nie udało się przywrócić pliku: ' .. tostring(restoreError) ..
                    '. Oryginał eksportu jest w: ' .. backup)
            end
            error(installError or 'Nie można podmienić eksportu.')
        end
        LrFileUtils.delete(backup)
    end)
    LrFileUtils.delete(temporary)
    LrFileUtils.delete(log)
    if not ok then error(err) end
end

function provider.postProcessRenderedPhotos(functionContext, filterContext)
    local p = filterContext.propertyTable
    local options, validationError = Frame.validate(p.frameWidthPercent, p.frameColor, p.frameMagick)
    if options and options.width ~= 0 then
        local ok, path = LrTasks.pcall(Magick.find, options.executable, WIN_ENV)
        if ok then options.executable = path else options, validationError = nil, tostring(path) end
    end
    for sourceRendition, rendition in filterContext:renditions { stopIfCanceled = true } do
        local success, pathOrError = sourceRendition:waitForRender()
        if not success then
            rendition:renditionIsDone(false, pathOrError)
        elseif not options then
            rendition:renditionIsDone(false, validationError)
        else
            local ok, err = LrTasks.pcall(function()
                process(options, pathOrError, p)
            end)
            if ok then
                rendition:renditionIsDone(true)
            else
                rendition:renditionIsDone(false, tostring(err))
            end
        end
    end
end

return provider
