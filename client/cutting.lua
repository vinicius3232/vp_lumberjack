-- vp_lumberjack v2 — ESTÁGIO Corte (client): derrubar (motosserra + queda) → cortar em
-- toras → carregar no garfo do telehandler → entregar no stand. Server valida tudo.

local active = false
local trees = {}          -- [id] = { obj, blip, cuttable }
local busyTree = nil      -- id em processamento local (suprime o swap p/ toco)
local standBlip = nil

--------------------------------------------------------------------------------
-- Props das árvores
--------------------------------------------------------------------------------
local function setBlip(id, cuttable)
    local t = trees[id]; if not t then return end
    if t.blip and DoesBlipExist(t.blip) then RemoveBlip(t.blip) end
    local c = Config.Cutting.trees[id]
    t.blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(t.blip, Config.Cutting.blip and Config.Cutting.blip.sprite or 1)
    SetBlipScale(t.blip, 0.6)
    SetBlipColour(t.blip, cuttable and 2 or 1)
    SetBlipAsShortRange(t.blip, true)
end

local function startFell(id) end -- fwd

local function setVisual(id, cuttable)
    local t = trees[id]; if not t then t = {}; trees[id] = t end
    t.cuttable = cuttable
    if t.obj and DoesEntityExist(t.obj) then
        exports.ox_target:removeLocalEntity(t.obj, 'vp_lumberjack_fell')
        DeleteEntity(t.obj)
    end
    local coord = Config.Cutting.trees[id]
    local model = cuttable and Config.Assets.props.tree or Config.Assets.props.stump
    if not lib.requestModel(model, 7000) then return end
    local obj = CreateObject(model, coord.x, coord.y, coord.z, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    SetEntityHeading(obj, (id * 37) % 360)
    FreezeEntityPosition(obj, true)
    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(model)
    t.obj = obj
    if cuttable then
        exports.ox_target:addLocalEntity(obj, {
            { name = 'vp_lumberjack_fell', icon = 'fas fa-tree', label = locale('tree_target_cut'),
              distance = 2.5, onSelect = function() startFell(id) end },
        })
    end
    setBlip(id, cuttable)
end

--------------------------------------------------------------------------------
-- Motosserra na mão (cosmético)
--------------------------------------------------------------------------------
local function giveChainsawProp()
    local model = Config.Assets.props.chainsaw
    if not lib.requestModel(model, 4000) then return nil end
    local pc = GetEntityCoords(cache.ped)
    local prop = CreateObject(model, pc.x, pc.y, pc.z, true, true, false)
    local bone = GetPedBoneIndex(cache.ped, 28422) -- SKEL_R_Hand
    AttachEntityToEntity(prop, cache.ped, bone, 0.12, 0.0, -0.02, 90.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return prop
end

local function removeProp(prop)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end

--------------------------------------------------------------------------------
-- Queda da árvore (anim por rotação do prop)
--------------------------------------------------------------------------------
local function fallTree(obj, fallDir)
    local yaw = GetHeadingFromVector_2d(fallDir.x, fallDir.y)
    SetEntityHeading(obj, yaw)
    local steps = math.max(8, math.floor(Config.Cutting.fellAnimTime / 33))
    for i = 1, steps do
        local pitch = -82.0 * (i / steps)
        SetEntityRotation(obj, pitch, 0.0, yaw, 2, true)
        Wait(33)
    end
end

--- Checa veículo no caminho da queda (exclui o telehandler do jogador).
local function fallPathBlocked(treeCoords, fallDir)
    local mid = treeCoords + (fallDir * 5.0)
    local veh = GetClosestVehicle(mid.x, mid.y, mid.z, Config.Cutting.fellCheckRadius, 0, 70)
    if veh and veh ~= 0 and veh ~= VPL.GetJobVehicle() then return true end
    return false
end

--------------------------------------------------------------------------------
-- Fluxo de corte
--------------------------------------------------------------------------------
startFell = function(id)
    if busyTree then return end
    if IsPedInAnyVehicle(cache.ped, false) then
        VPL.Notify('error', 'need_get_out'); return
    end

    local ok, reason = lib.callback.await('vp_lumberjack:cutting:beginFell', false, id)
    if not ok then
        VPL.Notify('error', VPL.Err(reason, {
            need_chainsaw = 'need_chainsaw', too_far = 'cut_too_far',
            not_cuttable = 'cut_not_cuttable', no_session = 'no_session',
        }))
        return
    end

    busyTree = id
    local treeCoords = Config.Cutting.trees[id]
    local fallDir = GetEntityCoords(cache.ped) - vector3(treeCoords.x, treeCoords.y, treeCoords.z)
    fallDir = fallDir / (#fallDir + 0.001)   -- normaliza (cai p/ longe do player)
    fallDir = vector3(-fallDir.x, -fallDir.y, 0.0)

    local saw = giveChainsawProp()
    VPL.PlayChainsaw(cache.ped)

    -- skillcheck (precisão) + barra de derrubada
    local pass = true
    if Config.Cutting.skillCheck and #Config.Cutting.skillCheck > 0 then
        pass = lib.skillCheck(Config.Cutting.skillCheck)
    end
    if pass then
        pass = lib.progressBar({
            duration = Config.Cutting.fellDuration, label = locale('cut_felling'),
            canCancel = true, disable = { move = true, car = true, combat = true },
            anim = { dict = Config.Assets.cutAnim.dict, clip = Config.Assets.cutAnim.clip },
        })
    end
    if not pass then
        removeProp(saw); VPL.StopChainsaw(); TriggerServerEvent('vp_lumberjack:cutting:cancelFell', id)
        busyTree = nil; VPL.Notify('inform', 'cut_cancelled'); return
    end

    -- obstáculo no caminho da queda
    if fallPathBlocked(vector3(treeCoords.x, treeCoords.y, treeCoords.z), fallDir) then
        removeProp(saw); VPL.StopChainsaw(); TriggerServerEvent('vp_lumberjack:cutting:cancelFell', id)
        busyTree = nil; VPL.Notify('error', 'fell_blocked'); return
    end

    local fok = lib.callback.await('vp_lumberjack:cutting:finishFell', false, id)
    if not fok then
        removeProp(saw); VPL.StopChainsaw(); busyTree = nil; VPL.Notify('error', 'cut_failed'); return
    end

    -- derruba visualmente
    local t = trees[id]
    if t and t.obj and DoesEntityExist(t.obj) then
        exports.ox_target:removeLocalEntity(t.obj, 'vp_lumberjack_fell')
        FreezeEntityPosition(t.obj, false)   -- libera p/ a anim de rotação da queda
        fallTree(t.obj, fallDir)
    end

    -- cortar em toras
    local cut = lib.progressBar({
        duration = Config.Cutting.cutDuration, label = locale('cut_logs'),
        canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { dict = Config.Assets.cutAnim.dict, clip = Config.Assets.cutAnim.clip },
    })
    removeProp(saw); VPL.StopChainsaw()
    if not cut then
        -- deixou a árvore caída; vira toco e libera (não ganhou nada)
        if t and t.obj and DoesEntityExist(t.obj) then DeleteEntity(t.obj) end
        setVisual(id, false); busyTree = nil
        VPL.Notify('inform', 'cut_cancelled'); return
    end

    -- vira fardo de toras (carga do garfo)
    if t and t.obj and DoesEntityExist(t.obj) then DeleteEntity(t.obj) end
    local lm = Config.Assets.props.woodpile
    if not lib.requestModel(lm, 5000) then busyTree = nil; return end
    local bundle = CreateObject(lm, treeCoords.x, treeCoords.y, treeCoords.z, false, false, false)
    PlaceObjectOnGroundProperly(bundle)
    SetEntityHeading(bundle, GetHeadingFromVector_2d(fallDir.x, fallDir.y))
    FreezeEntityPosition(bundle, true)
    SetModelAsNoLongerNeeded(lm)

    VPL.Notify('inform', 'cut_load_ready')

    -- carregar no garfo e levar ao stand
    local stand = Config.Cutting.stand
    local delivered = VPL.ForkCarry(
        bundle,
        GetEntityCoords(bundle),
        { coords = vector3(stand.coords.x, stand.coords.y, stand.coords.z), heading = stand.coords.w,
          radius = Config.Fork.alignDistance + 0.5 },
        function()
            local dok, ddata = lib.callback.await('vp_lumberjack:cutting:deliver', false)
            if dok then VPL.Notify('success', 'cut_paid', VPL.Money(ddata.pay))
            else VPL.Notify('error', VPL.Err(ddata, { no_load = 'cut_failed', stand_far = 'stand_far' })) end
        end
    )

    if DoesEntityExist(bundle) then DeleteEntity(bundle) end
    -- se o job acabou durante o carregamento, o teardown já limpou; não recria prop
    if active then setVisual(id, false) end   -- toco (server marcou não-cortável; respawn devolve)
    busyTree = nil
end

--------------------------------------------------------------------------------
-- Sync + setup/teardown por sessão
--------------------------------------------------------------------------------
RegisterNetEvent('vp_lumberjack:cutting:update', function(id, cuttable)
    if not active then return end
    if id == busyTree then return end   -- a sequência local controla o visual
    if not trees[id] then return end
    setVisual(id, cuttable)
end)

local function setupCutting()
    if active then return end
    active = true
    local state = lib.callback.await('vp_lumberjack:cutting:getState', false)
    local known = {}
    if type(state) == 'table' then
        for i = 1, #state do known[state[i].id] = true; setVisual(state[i].id, state[i].cuttable) end
    end
    for id = 1, #Config.Cutting.trees do
        if not known[id] then setVisual(id, true) end
    end
    local s = Config.Cutting.stand
    standBlip = AddBlipForCoord(s.coords.x, s.coords.y, s.coords.z)
    SetBlipSprite(standBlip, 237); SetBlipColour(standBlip, 56); SetBlipScale(standBlip, 0.8)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(s.label); EndTextCommandSetBlipName(standBlip)
end

local function teardownCutting()
    active = false; busyTree = nil
    for id, t in pairs(trees) do
        if t.obj and DoesEntityExist(t.obj) then
            exports.ox_target:removeLocalEntity(t.obj, 'vp_lumberjack_fell'); DeleteEntity(t.obj)
        end
        if t.blip and DoesBlipExist(t.blip) then RemoveBlip(t.blip) end
    end
    trees = {}
    if standBlip and DoesBlipExist(standBlip) then RemoveBlip(standBlip); standBlip = nil end
end

AddEventHandler('vp_lumberjack:client:jobStarted', function(jobKey)
    if jobKey == 'cutting' then setupCutting() end
end)
AddEventHandler('vp_lumberjack:client:jobEnded', function(jobKey)
    if jobKey == 'cutting' then teardownCutting() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then teardownCutting() end
end)
