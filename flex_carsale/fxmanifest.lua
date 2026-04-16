fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'flex_carsale'
description 'Car sale script'
version '0.0.1'

ui_page('ui/index.html') 

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'shared/config.lua',
    'shared/sv_shared.lua',
    'client/bridge/*.lua',
    'server/bridge/*.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
    'data/*.json',
    '**/config.lua',
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
}

dependencies {
    'ox_lib',
    'qbx_core'
}