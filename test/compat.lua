local resourceDir = (... and ... ~= '') and ... or '.'

local function read(path)
    local file = assert(io.open(('%s/%s'):format(resourceDir, path), 'rb'))
    local source = file:read('*a')
    file:close()
    return source
end

local function loadResource(path, environment)
    local chunk, err = load(read(path), ('@@ox_lib/%s'):format(path:gsub('^resource/', 'resource/')), 't', environment or _ENV)
    assert(chunk, err)
    return chunk()
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, message)
    if not value then error(message, 2) end
end

local function makeBaseEnvironment()
    local environment = setmetatable({}, { __index = _G })
    environment._ENV = environment
    environment.IsDuplicityVersion = function() return false end
    environment.GetGameName = function() return 'fivem' end
    environment.GetCurrentResourceName = function() return 'ox_lib' end
    environment.GetResourceState = function() return 'started' end
    environment.GetInvokingResource = function() return nil end
    environment.GetConvarInt = function(_, fallback) return fallback end
    environment.GetConvar = function(_, fallback) return fallback end
    environment.GetNumResourceMetadata = function() return 0 end
    environment.GetResourceMetadata = function() return nil end
    environment.json = {
        decode = function()
            return { ui = { cancel = 'Cancel', close = 'Close', confirm = 'Confirm', more = 'More...' } }
        end,
    }
    environment.PlayerId = function() return 7 end
    environment.GetPlayerServerId = function() return 42 end
    environment.RegisterNetEvent = function() end
    environment.AddEventHandler = function() end
    environment.SetTimeout = function() end
    environment.Wait = function() end
    environment.msgpack = { setoption = function() end }
    environment.Citizen = {
        CreateThreadNow = function() end,
        Await = function(value) return value end,
    }
    environment.LoadResourceFile = function(resource, path)
        if resource ~= 'ox_lib' then return nil end
        -- Stock Lua does not implement FiveM's CfxLua operators used by the
        -- upstream require module (for example optional chaining). The shim
        -- test only needs a stable consumer-local require value here.
        if path == 'imports/require/shared.lua' then
            return 'return function() end'
        end

        local ok, value = pcall(read, path)
        return ok and value or nil
    end
    return environment
end

local function testResourceBridge()
    local environment = makeBaseEnvironment()
    local registered = {}
    local calls = {}
    local handlers = {}
    local stateBagHandlers = {}
    local serverEvents = {}
    local deletedEntities = {}
    local warnings = {}
    local commands = {}
    local keyMappings = {}
    local nextObject = 1000
    local stateBagPlayer = 2
    local qblib
    qblib = setmetatable({}, {
        __index = function(_, method)
            return function(self, ...)
                equal(self, qblib, ('%s must use FiveM colon export dispatch'):format(method))
                calls[#calls + 1] = { method = method, args = table.pack(...) }
                return method
            end
        end,
    })

    environment.exports = setmetatable({ qblib = qblib }, {
        __call = function(_, name, handler)
            registered[name] = handler
        end,
    })
    environment.GetResourceState = function(resource)
        return resource == 'qblib' and 'started' or 'missing'
    end

    loadResource('resource/init.lua', environment)
    equal(registered.hasLoaded(), true, 'resource must report loaded when qblib is started')

    environment.GetInvokingResource = function() return 'consumer-resource' end
    environment.require = function(path)
        equal(path, 'resource.settings', 'UI bridge must read ox_lib player settings')
        return { locale = 'en', notification_audio = false, notification_position = 'top-right' }
    end
    environment.table = setmetatable({
        clone = function(value)
            local copy = {}
            for key, item in pairs(value) do copy[key] = item end
            return copy
        end,
        pack = table.pack,
        unpack = table.unpack,
        type = function(value)
            if next(value) == nil then return 'empty' end
            for index = 1, #value do
                if value[index] == nil then return 'hash' end
            end
            for key in pairs(value) do
                if type(key) ~= 'number' or key < 1 or key > #value or key % 1 ~= 0 then return 'hash' end
            end
            return 'array'
        end,
    }, { __index = table })
    environment.TriggerEvent = function() end
    environment.TriggerServerEvent = function(name, value)
        serverEvents[#serverEvents + 1] = { name = name, value = value }
    end
    environment.RegisterNetEvent = function(name, handler)
        if handler then handlers[name] = handler end
    end
    environment.RegisterCommand = function(name, handler)
        commands[name] = handler
    end
    environment.RegisterKeyMapping = function(name, description, device, key)
        keyMappings[name] = { description = description, device = device, key = key }
    end
    environment.AddEventHandler = function(name, handler)
        handlers[name] = handler
    end
    environment.AddStateBagChangeHandler = function(key, _, handler)
        stateBagHandlers[key] = handler
    end
    environment.LocalPlayer = { state = { invBusy = 'previous' } }
    environment.IsEntityDead = function() return false end
    environment.IsPedRagdoll = function() return false end
    environment.IsPedCuffed = function() return false end
    environment.IsPedFalling = function() return false end
    environment.IsPedSwimming = function() return false end
    environment.SetModelAsNoLongerNeeded = function() end
    environment.IsModelAPed = function() return false end
    environment.IsModelAVehicle = function() return false end
    local vector
    vector = function(x, y, z)
        return setmetatable({ x = x, y = y, z = z }, {
            __sub = function(left, right)
                return vector(left.x - right.x, left.y - right.y, left.z - right.z)
            end,
        })
    end
    environment.GetModelDimensions = function() return vector(0, 0, 0), vector(1, 1, 1) end
    environment.GetEntityCoords = function() return vector(1, 2, 3) end
    environment.CreateObject = function()
        nextObject = nextObject + 1
        return nextObject
    end
    environment.AttachEntityToEntity = function() end
    environment.GetPedBoneIndex = function(_, bone) return bone end
    environment.GetPlayerFromStateBagName = function() return stateBagPlayer end
    environment.GetPlayerPed = function() return 222 end
    environment.GetPlayerServerId = function() return 22 end
    environment.DoesEntityExist = function() return true end
    environment.DeleteEntity = function(entity) deletedEntities[#deletedEntities + 1] = entity end
    rawset(environment.lib, 'locale', function() end)
    environment.locale = function(key) return key end
    rawset(environment.lib, 'requestModel', function(model)
        if model == 'invalid' then error('invalid model') end
        return 123
    end)
    rawset(environment.lib, 'print', {
        warn = function(message) warnings[#warnings + 1] = message end,
        error = function(message) error(message) end,
    })
    environment.cache.ped = 111
    loadResource('resource/locale/client.lua', environment)
    loadResource('resource/progressProps/client.lua', environment)
    loadResource('resource/interface/client.lua', environment)

    equal(#calls, 1, 'locale bootstrap must reach the shared qblib NUI')
    equal(calls[1].method, 'ox_setLocale', 'locale bootstrap must use the qblib locale ingress')
    equal(calls[1].args[1], 'en', 'locale bootstrap must preserve the persisted locale key')
    equal(calls[1].args[2].ui.confirm, 'Confirm', 'locale bootstrap must forward the ox locale catalog')
    equal(calls[1].args[3], 'ox_lib', 'locale bootstrap must be owned by the compatibility resource')
    truthy(commands.cancelprogress, 'the upstream cancelprogress command must remain registered')
    equal(keyMappings.cancelprogress.device, 'keyboard', 'cancelprogress must remain a remappable keyboard binding')
    equal(keyMappings.cancelprogress.key, 'x', 'cancelprogress must retain the upstream default key')

    local required = {
        'alertDialog', 'closeAlertDialog', 'setClipboard', 'showContext', 'registerContext',
        'getOpenContextMenu', 'hideContext', 'inputDialog', 'closeInputDialog', 'setNuiFocus',
        'resetNuiFocus', 'registerMenu', 'showMenu', 'hideMenu', 'setMenuOptions', 'getOpenMenu',
        'notify', 'defaultNotify', 'progressBar', 'progressCircle', 'cancelProgress',
        'progressActive', 'registerRadial', 'getCurrentRadialId', 'hideRadial', 'addRadialItem',
        'removeRadialItem', 'clearRadialItems', 'disableRadial', 'showRadialMenu', 'skillCheck',
        'cancelSkillCheck', 'skillCheckActive', 'showTextUI', 'hideTextUI', 'isTextUIOpen',
        'getLocaleKey', 'setLocale',
    }

    for i = 1, #required do
        truthy(registered[required[i]], ('missing ox_lib export %s'):format(required[i]))
    end

    equal(registered.setLocale('de'), nil, 'setLocale must retain the upstream nil return')
    local localeCall = calls[#calls]
    equal(localeCall.method, 'ox_setLocale', 'setLocale must update the shared qblib NUI locale')
    equal(localeCall.args[1], 'de', 'setLocale must forward the selected key')
    equal(localeCall.args[3], 'consumer-resource', 'setLocale must retain consumer ownership')

    local payload = { description = 'hello' }
    equal(registered.notify(payload), 'ox_notify', 'notify must return the qblib result')
    local call = calls[#calls]
    equal(call.method, 'ox_notify', 'notify must use the matching qblib export')
    truthy(call.args[1] ~= payload, 'notify must not mutate the caller payload')
    equal(call.args[1].description, payload.description, 'notify description must be preserved')
    equal(call.args[1].position, 'top-right', 'notify must apply the persisted default position')
    equal(call.args[2], 'consumer-resource', 'notify must preserve original caller ownership')

    local progressData = {
        duration = 1000,
        canCancel = true,
        prop = {
            { model = 'valid', pos = vector(0, 0, 0), rot = vector(0, 0, 0) },
            { model = 'invalid', pos = vector(0, 0, 0), rot = vector(0, 0, 0) },
            { pos = vector(0, 0, 0), rot = vector(0, 0, 0) },
        },
    }
    equal(registered.progressBar(progressData), 'ox_progressBar', 'progress must retain the qblib result')
    equal(#progressData.prop, 1, 'invalid progress props must be removed without aborting progress')
    call = calls[#calls]
    equal(call.method, 'ox_progressBar', 'progress must use the matching qblib export')
    equal(call.args[1].prop, progressData.prop, 'qblib must create the local player progress props')
    equal(call.args[1].canCancel, true, 'progress must preserve the upstream cancellation contract')
    equal(environment.LocalPlayer.state.invBusy, 'previous', 'progress must restore the prior inventory busy state')
    equal(serverEvents[#serverEvents - 1].name, 'ox_lib:progressProps', 'progress props must be published')
    equal(serverEvents[#serverEvents - 1].value, progressData.prop, 'published progress props must use the validated set')
    equal(serverEvents[#serverEvents].value, nil, 'progress props must be cleared after completion')
    equal(#warnings, 2, 'each invalid progress prop must produce compatibility telemetry')
    equal(registered.progressActive(), nil, 'completed progress must release the shim-owned lifecycle state')
    local cancelOk, cancelError = pcall(registered.cancelProgress)
    equal(cancelOk, false, 'cancelProgress must reject when the shim has no active progress')
    truthy(tostring(cancelError):find('No progress bar is active', 1, true), 'cancelProgress must retain the upstream error')

    local beforeInvalidEvents = #serverEvents
    registered.progressBar({
        duration = 1000,
        prop = { model = 'invalid', pos = vector(0, 0, 0), rot = vector(0, 0, 0) },
    })
    equal(#serverEvents, beforeInvalidEvents + 1, 'an invalid single prop must publish exactly one clearing update')
    equal(serverEvents[#serverEvents].value, nil, 'an invalid single prop must clear replicated prop state')

    local stateHandler = stateBagHandlers['lib:progressProps']
    truthy(stateHandler, 'remote progress prop statebag observer must be registered')
    stateBagPlayer = 7
    local objectBeforeOwnState = nextObject
    stateHandler('player:42', 'lib:progressProps', {
        model = 'valid', pos = vector(0, 0, 0), rot = vector(0, 0, 0),
    }, nil, false)
    equal(nextObject, objectBeforeOwnState, 'the qblib-owned local prop must not be duplicated by its statebag update')

    stateBagPlayer = 2
    stateHandler('player:22', 'lib:progressProps', {
        model = 'valid', pos = vector(0, 0, 0), rot = vector(0, 0, 0),
    }, nil, false)
    stateHandler('player:22', 'lib:progressProps', nil, nil, false)
    equal(#deletedEntities, 1, 'clearing a remote progress statebag must delete its attached prop')

    local beforeCalls = #calls
    local beforeEvents = #serverEvents
    environment.IsEntityDead = function() return true end
    equal(registered.progressCircle({ duration = 1000 }), nil, 'disallowed progress must return nil before starting')
    equal(#calls, beforeCalls, 'disallowed progress must not reach qblib')
    equal(#serverEvents, beforeEvents, 'disallowed progress must not publish props')

    environment.GetResourceState = function() return 'stopped' end
    truthy(registered.hasLoaded():find('qblib must be started', 1, true), 'hasLoaded must expose its load-order failure')
end

local function testConsumerImport()
    local environment = makeBaseEnvironment()
    local calls = {}
    local oxExports = setmetatable({}, {
        __index = function(_, method)
            if method == 'hasLoaded' then return function() return true end end

            return function(receiver, ...)
                equal(receiver, nil, ('consumer proxy must preserve ox dot-dispatch receiver for %s'):format(method))
                calls[#calls + 1] = { method = method, args = table.pack(...) }
                if method == 'cache' then return false end
                return method
            end
        end,
    })

    environment.exports = { ox_lib = oxExports }
    environment.GetCurrentResourceName = function() return 'consumer-resource' end

    loadResource('init.lua', environment)
    equal(environment.lib.name, 'ox_lib', 'consumer import must install lib')
    equal(environment.lib.context, 'client', 'consumer import must expose the realm')
    equal(environment.cache.resource, 'consumer-resource', 'cache ownership must be consumer-local')
    equal(environment.cache.playerId, 7, 'consumer cache must prime playerId')
    equal(environment.cache.serverId, 42, 'consumer cache must prime serverId')
    equal(environment.require, environment.lib.require, 'consumer import must replace require with lib.require')

    local payload = { description = 'forward me' }
    equal(environment.lib.notify(payload), 'notify', 'unknown lazy modules must fall through to ox_lib exports')
    local call = calls[#calls]
    equal(call.method, 'notify', 'consumer proxy must select the requested export')
    equal(call.args[1], payload, 'consumer proxy must preserve arguments')

    local missing = makeBaseEnvironment()
    missing.exports = { ox_lib = oxExports }
    missing.GetCurrentResourceName = function() return 'consumer-resource' end
    missing.GetResourceState = function() return 'stopped' end
    local ok, err = pcall(loadResource, 'init.lua', missing)
    equal(ok, false, 'consumer import must reject an ox_lib load-order violation')
    truthy(tostring(err):find('ox_lib must be started before this resource', 1, true), 'load-order error must match upstream')
end

local function testStateBagRequestValidation()
    local environment = makeBaseEnvironment()
    local requestSetStateBag
    local writes, networkIds = {}, {}
    local function pipeline()
        local value = { hooks = { true } }
        function value:registerHook(callback) self.hooks[#self.hooks + 1] = callback end
        function value:dispatch()
            return setmetatable({ ok = true, size = 1 }, { __close = function() end })
        end
        return value
    end

    environment.lib = {
        hook = { new = function() return pipeline() end },
        callback = { register = function(name, callback)
            equal(name, 'ox_lib:requestSetStateBag', 'state request callback name')
            requestSetStateBag = callback
        end },
    }
    environment.string = setmetatable({ strsplit = function(separator, value)
        return value:match('^([^' .. separator .. ']+)' .. separator .. '(.+)$')
    end }, { __index = string })
    environment.NetworkGetEntityFromNetworkId = function(networkId)
        networkIds[#networkIds + 1] = networkId
        return networkId + 1000
    end
    environment.msgpack = { pack = function() return 'packed' end }
    environment.SetStateBagValue = function(...)
        writes[#writes + 1] = { ... }
    end
    environment.lib.vehicle = { new = function() return { get = function() end } end }

    loadResource('resource/state/server.lua', environment)
    truthy(requestSetStateBag, 'state write callback must be registered')

    local invalid = {
        { false, 'key', 1 }, { 'entity:not-a-number', 'key', 1 },
        { 'entity:0', 'key', 1 }, { 'player:7', 'key', 2 },
        { 'player:42', '', 2 }, { 'player:42', 'key', 0 },
    }
    for i = 1, #invalid do
        local request = invalid[i]
        equal(requestSetStateBag(42, request[1], request[2], true, request[3]), false,
            'malformed state requests must fail closed')
    end
    equal(#writes, 0, 'invalid requests must not write state')
    equal(#networkIds, 0, 'invalid requests must not resolve a network entity')

    equal(requestSetStateBag(42, 'player:42', 'safe', true, 2), true,
        'a valid authorized player request should reach its hook pipeline')
    equal(writes[1][1], 'player:42', 'valid request bag')
    equal(writes[1][2], 'safe', 'valid request key')
end

testResourceBridge()
testConsumerImport()
testStateBagRequestValidation()
print('ok - ox_lib import and qblib forwarding contract')
