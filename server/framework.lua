-- vp_lumberjack v2 — Sessão de trabalho (server-authoritative).
-- O pagamento ACUMULA durante o job e só é creditado quando o jogador
-- DEVOLVE o veículo. Cancelar (morte/distância/dano) descarta o acumulado.

-- Sessions[src] = { job, earnings, vehicle, vehicleType, spawnIndex }
local Sessions = {}

--- @param src number
--- @return table|nil
function VPL.GetSession(src)
    return Sessions[src]
end

--- Soma ao acumulado do job atual (chamado pelos módulos cutting/stacking/delivery).
--- @param src number
--- @param amount number
--- @param breakdown? table  ex.: { km = 7.8 } p/ relatório
function VPL.AddEarning(src, amount, breakdown)
    local s = Sessions[src]
    if not s or amount <= 0 then return end
    s.earnings = s.earnings + amount
    if breakdown and breakdown.km then s.travelKm = (s.travelKm or 0) + breakdown.km end
end

--- @param src number
--- @return string|nil jobKey
function VPL.GetJobOf(src)
    local s = Sessions[src]
    return s and s.job
end

--------------------------------------------------------------------------------
-- Escolha de ponto de spawn livre
--------------------------------------------------------------------------------
local function freeSpawnIndex()
    local used = {}
    for _, s in pairs(Sessions) do
        if s.spawnIndex then used[s.spawnIndex] = true end
    end
    for i = 1, #Config.JobCenter.vehicleSpawns do
        if not used[i] then return i end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Iniciar job
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:startJob', function(src, jobKey)
    if not Security.IsValidSource(src) then return false end
    if Security.IsOnCooldown(src, 'startJob', Config.Cooldowns.startJob) then return false, 'cooldown' end
    if Sessions[src] then return false, 'already_working' end
    if not VPL.CanWork(src) then return false, 'no_job' end

    local job = Config.Jobs[jobKey]
    if not job then
        Security.LogSuspicious(src, 'startJob', 'jobKey=' .. tostring(jobKey))
        return false, 'badjob'
    end
    if Security.DistanceTo(src, Config.JobCenter.coords) > 25.0 then return false, 'too_far' end

    local idx = freeSpawnIndex()
    if not idx then return false, 'spawns_full' end

    local model = Config.Assets.vehicles[job.vehicle]
    local veh = VPL.SpawnVehicle(src, model, Config.JobCenter.vehicleSpawns[idx])
    if not veh then return false, 'spawnfail' end

    Sessions[src] = {
        job         = jobKey,
        earnings    = 0,
        travelKm    = 0,
        vehicle     = veh,
        vehicleType = job.vehicle,
        spawnIndex  = idx,
    }
    -- netId p/ o watchdog do client checar dano do veículo de trabalho
    return true, { job = jobKey, netId = NetworkGetNetworkIdFromEntity(veh) }
end)

--------------------------------------------------------------------------------
-- Devolver veículo e finalizar (paga o acumulado)
--------------------------------------------------------------------------------
lib.callback.register('vp_lumberjack:returnVehicle', function(src)
    if not Security.IsValidSource(src) then return false end
    if Security.IsOnCooldown(src, 'returnVehicle', Config.Cooldowns.returnVehicle) then return false, 'cooldown' end

    local s = Sessions[src]
    if not s then return false, 'no_session' end

    -- jogador e veículo precisam estar na zona de devolução (proximity server-side)
    local rz = Config.JobCenter.returnZone
    if Security.DistanceTo(src, rz.coords) > rz.radius + 1.0 then return false, 'return_far' end
    if not s.vehicle or not DoesEntityExist(s.vehicle) then
        -- veículo sumiu (destruído?) — encerra sem pagar, libera a sessão
        Sessions[src] = nil
        return false, 'vehicle_gone'
    end
    if #(GetEntityCoords(s.vehicle) - rz.coords) > rz.radius + 2.0 then return false, 'return_far' end

    local earnings = s.earnings
    local km = s.travelKm or 0
    if earnings > 0 then VPL.Pay(src, earnings, 'vp_lumberjack-' .. s.job) end

    DeleteEntity(s.vehicle)
    Sessions[src] = nil
    return true, { earnings = earnings, km = km, job = s.job }
end)

--------------------------------------------------------------------------------
-- Cancelar job (watchdog do client: morte/distância/dano) — sem pagamento
--------------------------------------------------------------------------------
local function endSession(src, deleteVeh)
    local s = Sessions[src]
    if not s then return end
    if deleteVeh and s.vehicle and DoesEntityExist(s.vehicle) then DeleteEntity(s.vehicle) end
    Sessions[src] = nil
end

RegisterNetEvent('vp_lumberjack:cancelJob', function()
    local src = source
    if not Security.IsValidSource(src) then return end
    endSession(src, true)
end)

--------------------------------------------------------------------------------
-- Limpeza
--------------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    endSession(source, true)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Sessions) do endSession(src, true) end
end)
