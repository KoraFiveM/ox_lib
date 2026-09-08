AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == cache.resource then return end

    exports.qblib:ox_disposeOwner(resourceName)
end)
