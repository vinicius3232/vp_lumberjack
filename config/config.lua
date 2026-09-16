-- vp_lumberjack — Configuração central
-- 3 sub-jobs (corte / empilhamento / entrega). Pagamento ACUMULA e é pago só quando
-- você DEVOLVE o veículo. Cancela por morte / distância / dano.
-- Server-authoritative, sem DB (estado em runtime).

Config = {}

Config.Debug   = false
Config.Webhook = ''

-- Acesso ao job. RequireJob=false → aberto a todos (bico). true → exige job 'lumberjack'.
Config.RequireJob = false
Config.JobName    = 'lumberjack'

-- Item ox_inventory exigido p/ cortar (ver README). Toras/pallets são server-side (não item).
Config.Items = { chainsaw = 'chainsaw' }

-- Motosserra: som durante o corte + comando de volume.
-- O som padrão usa um native (placeholder). Pra som fiel, aponte VPL.PlayChainsaw
-- pro seu resource de áudio (xsound/InteractSound) — ver README.
Config.Chainsaw = {
    volumeCommand = 'serravolume',   -- /serravolume 0-100
    defaultVolume = 70,
    loopMs        = 600,             -- re-trigger do som enquanto corta
    sound = { set = 'DLC_HEIST_FLEECA_SOUNDSET', name = 'Drill_Pin_Break' }, -- placeholder native
}

--------------------------------------------------------------------------------
-- ASSETS — modelos NATIVOS do GTA por padrão (funcionam em qualquer servidor).
-- Se você tiver modelos custom (telehandler, empilhadeira, props de tora etc.),
-- basta trocar os nomes abaixo pelos seus — o código referencia só estes campos.
--------------------------------------------------------------------------------
Config.Assets = {
    vehicles = {
        telehandler = 'forklift',    -- corte: carrega as toras
        forklift    = 'forklift',    -- empilhamento
        truck       = 'flatbed',     -- entrega: carrega os pallets
        trailer     = 'trailerlogs', -- pátio de empilhamento (alvo dos pallets)
    },
    props = {
        chainsaw = 'prop_tool_consaw',   -- prop de motosserra na mão (cosmético)
        log      = 'prop_log_01',        -- tora cortada (reservado p/ uso futuro)
        woodpile = 'prop_woodpile_01a',  -- fardo de toras / pallet de lumber
        tree     = 'prop_tree_pine_02',  -- árvore em pé
        stump    = 'prop_tree_stump_01', -- toco
    },
    cutAnim = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
}

--------------------------------------------------------------------------------
-- CENTRO DO JOB — capataz, blip, pontos de spawn de veículo e zona de devolução
--------------------------------------------------------------------------------
Config.JobCenter = {
    ped    = 's_m_y_construct_01',
    coords = vector4(-552.9, 5324.4, 73.6, 21.0),     -- serraria de Paleto Forest
    blip   = { sprite = 237, color = 21, scale = 0.9, label = 'Lenhador — Serraria' },

    -- pontos onde os veículos de trabalho nascem (o framework escolhe um livre)
    vehicleSpawns = {
        vector4(-533.0, 5325.0, 73.6, 250.0),
        vector4(-536.5, 5329.5, 73.6, 250.0),
        vector4(-540.0, 5334.0, 73.6, 250.0),
    },

    -- zona p/ devolver o veículo e finalizar o job (receber o acumulado)
    returnZone = { coords = vector3(-528.0, 5320.0, 73.5), radius = 8.0 },
}

--------------------------------------------------------------------------------
-- CANCELAMENTO — condições que abortam o job e PERDEM o acumulado
--------------------------------------------------------------------------------
Config.Cancel = {
    cancelOnDeath          = true,
    -- Leash pelo VEÍCULO de trabalho (não pelo centro) — assim a Entrega pode ir longe,
    -- mas você não pode abandonar sua máquina e sair andando.
    maxDistanceFromVehicle  = 200.0,   -- m a pé do veículo de trabalho → cancela
    warnDistanceFromVehicle = 150.0,   -- m → aviso antes de cancelar
    engineHealthMin        = 250.0,    -- abaixo disso (motor) cancela
    bodyHealthMin          = 300.0,    -- abaixo disso (lataria) cancela
    warnHealth             = 500.0,    -- aviso de dano
    checkInterval          = 1000,     -- ms entre checagens do watchdog
}

--------------------------------------------------------------------------------
-- OS 3 SUB-JOBS — rótulos, veículo e tabela de pagamento (tudo pago server-side)
--------------------------------------------------------------------------------
-- NOTA DE BALANCE: valores ajustados p/ ~$350–480/min por job (corte mais lento porém
-- estável; entrega aposta na distância). Calibre com seu servidor — são ponto de partida.
Config.Jobs = {
    cutting = {
        label   = 'Corte de Árvores',
        comment = 'Motosserra + transportar as toras ao stand com o telehandler.',
        vehicle = 'telehandler',
        pay     = { perTree = 700 },        -- $ por árvore cortada+entregue (pago na devolução)
        order   = 1,
    },
    stacking = {
        label   = 'Empilhamento de Pallets',
        comment = 'Pegar pallets com a empilhadeira e encaixar nos trailers.',
        vehicle = 'forklift',
        pay     = { perPallet = 200 },      -- $ por pallet encaixado no trailer
        order   = 2,
    },
    delivery = {
        label   = 'Entrega de Lumber',
        comment = 'Levar os pallets até a obra com o caminhão. Mais longe = mais dinheiro.',
        vehicle = 'truck',
        pay     = { perDelivery = 150, perKm = 55 },  -- por pallet: 150 + 55*distanceKm
        order   = 3,
    },
}

--------------------------------------------------------------------------------
-- DETALHE POR JOB (refinado nas fases 2–4; já exposto p/ o framework)
--------------------------------------------------------------------------------

-- Corte (Fase 2)
Config.Cutting = {
    fellDuration = 9000,            -- ms cortando o tronco até cair
    fellMin      = 7000,            -- ms mínimo aceito pelo server (anti instant)
    cutDuration  = 6000,            -- ms cortando a árvore caída em toras
    interactRadius = 3.5,
    logsPerTree  = { min = 2, max = 3 },
    respawnMinutes = 20,
    fellCheckRadius = 4.5,          -- raio à frente p/ checar veículo no caminho da queda
    fellAnimTime = 1300,            -- ms da animação de queda da árvore
    skillCheck = { 'easy', 'medium' },
    stand = { coords = vector4(-558.6, 5310.7, 73.6, 200.0), radius = 6.0, label = 'Stand de toras' },
    trees = {
        vector3(-583.1, 5306.4, 70.2), vector3(-595.7, 5318.9, 69.5),
        vector3(-571.0, 5338.2, 70.9), vector3(-559.4, 5357.7, 72.1),
        vector3(-540.2, 5366.0, 73.8), vector3(-520.6, 5354.1, 75.2),
        vector3(-606.9, 5293.3, 68.4), vector3(-588.8, 5352.4, 71.6),
    },
}

-- Empilhamento (Fase 3)
Config.Stacking = {
    liftDuration = 5000,
    yard = { coords = vector3(-538.0, 5318.5, 73.5), radius = 14.0 },
    palletSpawns = {                -- onde os pallets aparecem p/ pegar
        vector4(-545.0, 5314.0, 73.5, 200.0),
        vector4(-548.0, 5317.0, 73.5, 200.0),
        vector4(-551.0, 5320.0, 73.5, 200.0),
    },
    trailerSpawns = {               -- trailers que recebem os pallets
        vector4(-525.0, 5312.0, 73.5, 110.0),
        vector4(-522.0, 5316.0, 73.5, 110.0),
    },
    palletsPerTrailer = 4,
}

-- Entrega (Fase 4)
Config.Delivery = {
    unloadDuration = 5000,
    truckCapacity  = 4,
    siteRadius     = 10.0,
    sites = {
        { coords = vector4(-150.6, -959.7, 254.0, 250.0), distanceKm = 7.8, label = 'Obra — Maze Bank' },
        { coords = vector4(  85.4, -1958.7,  20.7, 320.0), distanceKm = 8.4, label = 'Obra — Cypress Flats' },
        { coords = vector4(  -1.2,  6457.9,  31.4,  45.0), distanceKm = 1.6, label = 'Obra — Paleto Bay' },
        { coords = vector4(-1090.0, 2715.3,  18.9, 220.0), distanceKm = 5.2, label = 'Obra — Great Chaparral' },
    },
    blip = { sprite = 478, color = 5, scale = 0.8 },
}

--------------------------------------------------------------------------------
-- GARFO (telehandler/empilhadeira) — operação real, reusado pelas fases 2–4.
-- Dirigir o veículo até alinhar o GARFO com a zona marcada, [E] p/ pegar/soltar.
--------------------------------------------------------------------------------
Config.Fork = {
    grabKey       = 38,                       -- E
    alignDistance = 2.0,                       -- m: garfo até o marcador
    alignHeading  = 40.0,                      -- graus de tolerância de heading no drop
    forkBone      = 'forks',                   -- bone do garfo (fallback p/ offset se não existir)
    forkOffset    = vector3(0.0, 1.3, 0.1),    -- fallback: posição do garfo a partir do veículo
    loadAttach    = vector3(0.0, 1.1, 0.25),   -- onde a carga gruda no garfo
    markerSize    = vector3(2.5, 2.5, 1.0),
    markerColor   = { r = 60, g = 200, b = 90, a = 140 },
}

--------------------------------------------------------------------------------
-- ROUPA DE TRABALHO (Fase 5) — componentes de ped (ajuste por modelo se quiser)
--------------------------------------------------------------------------------
Config.Workwear = {
    -- mp_m_freemode_01 (masc.) / mp_f_freemode_01 (fem.)
    male = {
        { component = 11, drawable = 250, texture = 0 }, -- torso (jaqueta)
        { component = 8,  drawable = 15,  texture = 0 }, -- undershirt
        { component = 4,  drawable = 100, texture = 0 }, -- pernas
        { component = 6,  drawable = 25,  texture = 0 }, -- sapatos
    },
    female = {
        { component = 11, drawable = 250, texture = 0 },
        { component = 8,  drawable = 15,  texture = 0 },
        { component = 4,  drawable = 100, texture = 0 },
        { component = 6,  drawable = 25,  texture = 0 },
    },
}

--------------------------------------------------------------------------------
-- Cooldowns (ms) — anti-flood (server-side)
--------------------------------------------------------------------------------
Config.Cooldowns = {
    startJob     = 4000,
    returnVehicle = 2000,
    giveTool     = 5000,
    action       = 1200,    -- corte/lift/unload genérico
}
