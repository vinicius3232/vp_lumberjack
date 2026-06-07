-- vp_lumberjack v2 — ESTÁGIO Empilhamento (client): pegar pallets do pátio com a
-- empilhadeira (garfo) e encaixá-los nos trailers. Server valida o drop e paga por pallet.

local active = false
local pallets = {}     -- { ent, coords, slot }   (disponíveis no pátio)
local placed = {}      -- entidades já encaixadas nos trailers (p/ limpeza)
local trailers = {}    -- { ent, coords, heading, index, fill, full }
local carrying = nil   -- entidade do pallet no garfo
local dropped, totalCap = 0, 0
local yardBlip = nil
local shown = false

local function prompt(text)
    if text and not shown then lib.showTextUI(text); shown = true
    elseif not text and shown then lib.hideTextUI(); shown = false end
end

--------------------------------------------------------------------------------
-- Spawns
--------------------------------------------------------------------------------
local function spawnPallet(slot)
    local sp = Config.Stacking.palletSpawns[slot]
    local model = Config.Assets.props.woodpile
    if not lib.requestModel(model, 5000) then return end
    local ent = CreateObject(model, sp.x, sp.y, sp.z, false, false, false)
    PlaceObjectOnGroundProperly(ent)
    SetEntityHeading(ent, sp.w)
    FreezeEntityPosition(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    SetModelAsNoLongerNeeded(model)
    pallets[#pallets + 1] = { ent = ent, coords = GetEntityCoords(ent), slot = slot }
end

local function occupiedSlots()
    local set = {}
    for _, p in ipairs(pallets) do set[p.slot] = true end
    return set
end

local function refillPallets()
    local target = math.min(#Config.Stacking.palletSpawns, totalCap - dropped - (carrying and 1 or 0))
    local occ = occupiedSlots()
    for slot = 1, #Config.Stacking.palletSpawns do
        if #pallets >= target then break end
        if not occ[slot] then spawnPallet(slot); occ[slot] = true end
    end
end

local function spawnTrailer(index)
    local sp = Config.Stacking.trailerSpawns[index]
    local model = Config.Assets.vehicles.trailer
    if not lib.requestModel(model, 7000) then return end
    local ent = CreateVehicle(GetHashKey(model), sp.x, sp.y, sp.z, sp.w, false, false)
    FreezeEntityPosition(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    SetVehicleDoorsLocked(ent, 2)
    SetModelAsNoLongerNeeded(model)
    trailers[#trailers + 1] = {
        ent = ent, coords = vector3(sp.x, sp.y, sp.z), heading = sp.w,
        index = index, fill = 0, full = false,
    }
end

--------------------------------------------------------------------------------
-- Loop principal de operação do garfo
--------------------------------------------------------------------------------
local function nearestPallet(tip)
    local best, bestD
    for _, p in ipairs(pallets) do
        local d = #(tip - p.coords)
        if d <= Config.Fork.alignDistance and (not bestD or d < bestD) then best, bestD = p, d end
    end
    return best
end

local function nearestTrailer(veh, tip)
    local best, bestD
    for _, t in ipairs(trailers) do
        if not t.full then
            local d = #(tip - t.coords)
            if d <= Config.Fork.alignDistance + 1.5
               and VPL.HeadingDiff(GetEntityHeading(veh), t.heading) <= Config.Fork.alignHeading
               and (not bestD or d < bestD) then best, bestD = t, d end
        end
    end
    return best
end

local function runLoop()
    CreateThread(function()
        while active do
            Wait(0)
            -- só processa/desenha perto do pátio (economia quando longe, ex.: indo buscar veículo)
            if #(GetEntityCoords(cache.ped) - Config.Stacking.yard.coords) > Config.Stacking.yard.radius + 30.0 then
                Wait(450)
                goto continue
            end
            local veh = VPL.InForkVehicle()
            if not carrying then
                for _, p in ipairs(pallets) do VPL.DrawForkZone(p.coords) end
                local near = veh and nearestPallet(VPL.ForkTip(veh))
                if near then
                    prompt(locale('fork_grab'))
                    if IsControlJustReleased(0, Config.Fork.grabKey) then
                        VPL.ForkAttach(veh, near.ent)
                        carrying = near.ent
                        for i = #pallets, 1, -1 do if pallets[i] == near then table.remove(pallets, i) break end end
                    end
                else prompt(nil) end
            else
                for _, t in ipairs(trailers) do if not t.full then VPL.DrawForkZone(t.coords) end end
                local t = veh and nearestTrailer(veh, VPL.ForkTip(veh))
                if t then
                    prompt(locale('fork_drop'))
                    if IsControlJustReleased(0, Config.Fork.grabKey) then
                        prompt(nil)
                        local ok, data = lib.callback.await('vp_lumberjack:stacking:drop', false, t.index)
                        if ok then
                            t.fill = data.fill; t.full = data.full
                            local stackZ = t.coords.z + 0.4 + (t.fill - 1) * 0.55
                            local ent = carrying
                            VPL.ForkPlace(ent, vector3(t.coords.x, t.coords.y, stackZ), t.heading)
                            placed[#placed + 1] = ent
                            carrying = nil
                            dropped = dropped + 1
                            VPL.Notify('success', 'stack_paid', VPL.Money(data.pay))
                            if dropped < totalCap then refillPallets() end
                            if dropped >= totalCap then VPL.Notify('inform', 'stack_done') end
                        elseif data == 'full' then
                            VPL.Notify('error', 'stack_full')
                        else
                            VPL.Notify('error', VPL.Err(data, { too_far = 'stand_far' }))
                        end
                    end
                else prompt(nil) end
            end
            ::continue::
        end
    end)
end

--------------------------------------------------------------------------------
-- Setup / teardown por sessão
--------------------------------------------------------------------------------
local function setupStacking()
    if active then return end
    active = true
    carrying = nil; dropped = 0; pallets = {}; trailers = {}; placed = {}
    for i = 1, #Config.Stacking.trailerSpawns do spawnTrailer(i) end
    totalCap = #trailers * Config.Stacking.palletsPerTrailer
    refillPallets()

    local y = Config.Stacking.yard
    yardBlip = AddBlipForCoord(y.coords.x, y.coords.y, y.coords.z)
    SetBlipSprite(yardBlip, 478); SetBlipColour(yardBlip, 5); SetBlipScale(yardBlip, 0.8)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(Config.Jobs.stacking.label); EndTextCommandSetBlipName(yardBlip)

    runLoop()
end

local function teardownStacking()
    active = false
    prompt(nil)
    if carrying and DoesEntityExist(carrying) then DeleteEntity(carrying) end
    carrying = nil
    for _, p in ipairs(pallets) do if DoesEntityExist(p.ent) then DeleteEntity(p.ent) end end
    for _, e in ipairs(placed) do if DoesEntityExist(e) then DeleteEntity(e) end end
    for _, t in ipairs(trailers) do if DoesEntityExist(t.ent) then DeleteEntity(t.ent) end end
    pallets = {}; trailers = {}; placed = {}
    if yardBlip and DoesBlipExist(yardBlip) then RemoveBlip(yardBlip); yardBlip = nil end
end

AddEventHandler('vp_lumberjack:client:jobStarted', function(jobKey)
    if jobKey == 'stacking' then setupStacking() end
end)
AddEventHandler('vp_lumberjack:client:jobEnded', function(jobKey)
    if jobKey == 'stacking' then teardownStacking() end
end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then teardownStacking() end
end)
