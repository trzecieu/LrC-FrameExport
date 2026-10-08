local LrTasks = import 'LrTasks'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local Frame = dofile(LrPathUtils.child(_PLUGIN.path, 'Frame.lua'))
local Magick = {}

-- Call from an LrTasks asynchronous task: execute() can yield.
function Magick.find(manual, windows)
    local log = LrFileUtils.chooseUniqueFileName(
        LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'frameexport-discovery.txt'))
    local ok, result = LrTasks.pcall(function()
        local quote = function(value) return Frame.quote(value, windows) end
        local function run(command)
            local status = LrTasks.execute(command .. ' > ' .. quote(log) .. ' 2>&1')
            return status, LrFileUtils.readFile(log) or ''
        end
        local function probe(path)
            if not LrPathUtils.isAbsolute(path) or LrFileUtils.exists(path) ~= 'file' then return false end
            local quoted = LrTasks.pcall(quote, path)
            if not quoted then return false end
            -- Windows needs the outer quotes around the WHOLE command,
            -- including redirection, when the executable contains spaces.
            local command = quote(path) .. ' -version > ' .. quote(log) .. ' 2>&1'
            if windows then command = '"' .. command .. '"' end
            local status = LrTasks.execute(command)
            local report = LrFileUtils.readFile(log) or ''
            return status == 0 and report:match('Version: ImageMagick 7%.') ~= nil
        end
        if manual and manual ~= '' then
            assert(probe(manual), 'The specified path does not point to a working ImageMagick 7 executable: ' .. manual)
            return manual
        end
        local _, report = run(windows and 'where.exe magick.exe' or 'command -v magick')
        local candidates = {}
        for path in report:gmatch('[^\r\n]+') do if probe(path) then return path end end
        if windows then
            -- Lightroom launched from the desktop may have a different PATH.
            -- Read the standard system install locations without assuming C:.
            local _, programFiles = run('echo %ProgramFiles%')
            local _, programFiles32 = run('echo %ProgramFiles(x86)%')
            local folders = programFiles .. '\n' .. programFiles32
            for folder in folders:gmatch('[^\r\n]+') do
                if LrFileUtils.exists(folder) == 'directory' then
                    for entry in LrFileUtils.directoryEntries(folder) do
                        if LrPathUtils.leafName(entry):match('^ImageMagick%-7') then
                            candidates[#candidates + 1] = LrPathUtils.child(entry, 'magick.exe')
                        end
                    end
                end
            end
        else
            for _, path in ipairs({ '/opt/homebrew/bin/magick', '/usr/local/bin/magick',
                '/opt/local/bin/magick', '/usr/bin/magick' }) do
                candidates[#candidates + 1] = path
            end
        end
        for _, path in ipairs(candidates) do if probe(path) then return path end end
        error('ImageMagick 7 was not found. Install it and click Detect again, '
            .. 'or select the executable using Choose….')
    end)
    LrFileUtils.delete(log)
    if not ok then error(result) end
    return result
end

return Magick
