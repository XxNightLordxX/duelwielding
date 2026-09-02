fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'John Allday'
description 'Simple, server-validated dual wielding (akimbo) for QBox'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client.lua'
server_script 'server.lua'

dependencies {
    'ox_lib',
    'ox_inventory',
}
