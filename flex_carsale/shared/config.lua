Config = {}

Config.Debug = true
Config.CoreName = {
    qb = 'qb-core',
    esx = 'es_extended',
    ox = 'ox_core',
    ox_inv = 'ox_inventory',
    qbx = 'qbx_core',
    qb_radial = 'qb-radialmenu',
}

Config.Notify = {
    client = function(msg, type, time)
        lib.notify({
            title = msg,
            type = type,
            time = time or 5000,
        })
    end,
    server = function(src, msg, type, time)
        lib.notify(src, {
            title = msg,
            type = type,
            time = time or 5000,
        })
    end,
}

-- Multi-location support.
-- Add extra locations by duplicating the object below and changing key/coords.
-- These locations are used as defaults and serialized to JSON on first run.
-- After that, locations are loaded from data/locations.json
Config.Locations = {
    city = {
        label = 'City PDM',
        sellPoint = vector3(219.89, -892.34, 30.69),
        sellRadius = 30.0,
        saleSpots = {
            [1] = vector4(221.80, -896.07, 30.69, 317.95),
            [2] = vector4(226.05, -899.64, 30.69, 344.50),
            [3] = vector4(225.27, -888.50, 30.69, 186.24),
        },
        buyVehicle = vector4(213.0, -892.0, 30.69, 240.0),
    },
}

Config.DefaultLocation = 'city'

-- Sell interaction options (E interaction only)
Config.SellInteraction = {
    enabled = true,
    key = 38, -- E
    ped = {
        model = 'a_m_m_business_01',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
    }
}
