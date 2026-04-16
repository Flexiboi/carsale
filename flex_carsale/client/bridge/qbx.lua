if GetResourceState('qbx_core') ~= 'started' then return end

function GetPlayerData()
    return exports.qbx_core:GetPlayerData()
end