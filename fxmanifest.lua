fx_version 'cerulean'
games({ 'gta5' })

name 'Pulsar Fuel'
description 'Vehicle fuel consumption and gas station refueling'
author 'Artmines - maintained for Pulsar Framework'
url 'https://pulsarframe.work'
version 'v1.0.0'

version_check 'yes'
github 'https://github.com/PulsarFW/pulsar_fuel'

client_script '@pulsar_core/components/cl_error.lua'
shared_script '@pulsar_core/core/sh_pulsar.lua'
client_script '@pulsar_pwnzor/client/check.lua'

client_scripts({
	'config.lua',
	'shared/*.lua',
	'client/*.lua',
})

server_scripts({
	'config.lua',
	'shared/*.lua',
	'server/*.lua',
})

lua54 'yes'