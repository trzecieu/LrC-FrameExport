local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrView = import 'LrView'
local Frame = dofile(LrPathUtils.child(_PLUGIN.path, 'Frame.lua'))
local provider = {}

provider.exportPresetFields = {
    { key = 'frameWidthPercent', default = 10 },
    { key = 'frameHeightPercent', default = 10 },
    { key = 'frameColor', default = '#FFFFFF' },
    { key = 'frameMagick', default = WIN_ENV and 'C:\\Program Files\\ImageMagick-7.1.1-Q16-HDRI\\magick.exe' or '/opt/homebrew/bin/magick' },
}

function provider.sectionForFilterInDialog(f, properties)
    local bind = LrView.bind
    return {
        title = 'Ramka przy eksporcie',
        f:column {
            bind_to_object = properties,
            spacing = f:control_spacing(),
            f:static_text { title = 'Procent oznacza łączny przyrost wymiaru, po połowie na każdą stronę.' },
            f:row {
                f:static_text { title = 'Szerokość (%)', width = 140 },
                f:edit_field { value = bind 'frameWidthPercent', width_in_chars = 8 },
                f:static_text { title = 'Wysokość (%)' },
                f:edit_field { value = bind 'frameHeightPercent', width_in_chars = 8 },
            },
            f:row {
                f:static_text { title = 'Kolor (#RRGGBB)', width = 140 },
                f:edit_field { value = bind 'frameColor', width_in_chars = 12 },
            },
            f:row {
                f:static_text { title = 'Program magick', width = 140 },
                f:edit_field { value = bind 'frameMagick', width_in_chars = 45 },
            },
            f:static_text { title = 'ImageMagick 7 • JPEG / TIFF • ramka po skalowaniu i znaku wodnym' },
            f:static_text { title = '10% / 10% daje po 5% szerokości i wysokości na przeciwległych krawędziach.' },
        },
    }
end

local function process(options, path, settings)
    if options.width == 0 and options.height == 0 then return end
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
    local options, validationError = Frame.validate(p.frameWidthPercent,
        p.frameHeightPercent, p.frameColor, p.frameMagick)
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
