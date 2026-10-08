local LrView = import 'LrView'
local Updater = require 'Updater'
local provider = {}

function provider.startDialog(properties)
    properties.autoCheckUpdates = Updater.automatic()
    properties:removeObserver('autoCheckUpdates', provider)
    properties:addObserver('autoCheckUpdates', provider, function(_, _, _, value)
        Updater.setAutomatic(value)
    end)
    Updater.bind(properties)
end

function provider.endDialog(properties)
    properties:removeObserver('autoCheckUpdates', provider)
    Updater.unbind(properties)
end

function provider.sectionsForTopOfDialog(f, properties)
    Updater.bind(properties)
    return {
        {
            title = 'FrameExport updates',
            f:column {
                bind_to_object = properties,
                spacing = f:control_spacing(),
                f:static_text { title = LrView.bind 'updateVersion' },
                f:static_text { title = LrView.bind 'updateStatus', width_in_chars = 60, height_in_lines = -1 },
                f:checkbox { title = 'Check for updates automatically once a day (no notifications)',
                    value = LrView.bind 'autoCheckUpdates' },
                f:row {
                    f:push_button { title = 'Check for updates', enabled = LrView.bind 'updateCanCheck',
                        action = Updater.checkAsync },
                    f:push_button { title = 'Install update', enabled = LrView.bind 'updateCanInstall',
                        action = Updater.installAsync },
                },
                f:static_text { title = LrView.bind 'updateBackup', width_in_chars = 60, height_in_lines = -1 },
                f:static_text { title = 'Installation verifies SHA-256, waits for exports and keeps a backup.' },
            },
        },
    }
end

return provider
