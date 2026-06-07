# vp_lumberjack

Job de **lenhador** para QBox. Três sub-jobs com **operação de garfo** (empilhadeira/
telehandler), **pagamento acumulado pago só na devolução do veículo** e **cancelamento por
morte / distância / dano**. Server-authoritative, **sem DB** (estado em runtime), **sem NUI
HTML** (painel via `lib.registerContext`). 100% **assets nativos do GTA**.

Stack: qbx_core 1.23 · ox_lib 3.32 · ox_inventory 2.44 · ox_target · qbx_vehiclekeys.

---

## Como joga

Fale com o **capataz** na serraria (Paleto Forest) → painel escolhe 1 dos 3 serviços.
Cada serviço **spawna o veículo certo** e te dá a chave. O dinheiro **acumula** e só cai
quando você **devolve o veículo** na zona marcada. Morrer, se afastar demais do veículo de
trabalho ou detonar o veículo **cancela o serviço e perde o acumulado**.

| Serviço | Veículo | Fluxo |
|---|---|---|
| **① Corte** | telehandler | Motosserra (com som) → árvore **cai** (checa obstáculo) → cortar em toras → **garfo** carrega ao stand → devolve |
| **② Empilhamento** | empilhadeira | Pegar pallet do pátio com o **garfo** → encaixar no trailer (posição + heading) → devolve |
| **③ Entrega** | caminhão | Caminhão carregado → obra aleatória (**+$ quanto mais longe**) → descarregar pallet a pallet → devolve |

**Operação de garfo:** dirija o telehandler/empilhadeira até o **garfo** entrar na zona verde,
**[E]** pega; leve até o destino, alinhe o heading, **[E]** solta.

---

## Instalação

### 1. Item no ox_inventory (OBRIGATÓRIO — só 1)

Em `resources/[ox]/ox_inventory/data/items.lua`:

```lua
['chainsaw'] = {
    label = 'Motosserra',
    weight = 4500,
    stack = false,
    close = true,
    description = 'Ferramenta do lenhador. Necessária para derrubar árvores.',
},
```

> As toras e pallets são **estado de servidor** (não itens) — só a motosserra é item.

### 2. server.cfg

Está em `resources/[standalone]/`. Se já existe `ensure [standalone]` (ensure de grupo),
sobe automático. Senão: `ensure vp_lumberjack`. Locale pt: `setr ox:locale pt`.

---

## Assets

Usa **modelos nativos do GTA** (`forklift`, `flatbed`, `trailerlogs`, `prop_woodpile_01a`,
`prop_tree_pine_02`, `prop_tree_stump_01`, `prop_tool_consaw`...). Funciona em qualquer
servidor, sem depender de nenhum recurso externo.

Se você tiver **modelos custom** (um telehandler/empilhadeira melhor, props de tora etc.),
basta trocar os nomes em `Config.Assets` — o código referencia só esses campos. Modelos
inválidos **degradam sem crashar** (o prop simplesmente não aparece).

---

## Calibração (IMPORTANTE) — `Config.Fork`

A posição do garfo varia por modelo de veículo. Se o garfo não "pegar" a carga, ajuste,
olhando o marcador verde no jogo:

- `forkBone` — nome do bone do garfo (`forks`; cai pro offset abaixo se não existir).
- `forkOffset` — posição do garfo a partir do veículo (fallback).
- `alignDistance` / `alignHeading` — tolerância de posição/direção pra pegar/soltar.
- `loadAttach` — onde a carga gruda no garfo.

Ative `Config.Debug = true` pra ver as zonas do ox_target.

---

## Economia (ponto de partida — calibre)

`Config.Jobs[*].pay`: corte `perTree=700`; empilhamento `perPallet=200`;
entrega `perDelivery=150 + perKm=55×distanceKm` por pallet. Alvo ~$350–480/min por serviço.

## Comandos

- `/serravolume 0-100` — volume do som da motosserra (persiste por jogador).
  O som padrão é um *placeholder* nativo — aponte `VPL.PlayChainsaw` (em `client/polish.lua`)
  pro seu resource de áudio (xsound/InteractSound) pra som fiel.

---

## Segurança

Todo callback passa por `server/security.lua`: `IsValidSource` + cooldown + **proximity
server-side** + token `BeginAuth/ConsumeAuth` (anti instant/auto-clicker) no corte.
Pagamento sempre calculado no server; `distanceKm` da entrega é fixo do config (nunca do
client). `LogSuspicious` + webhook opcional (`Config.Webhook`).

## Estrutura

```
config/config.lua           tudo configurável
shared/utils.lua            VPL: RandInt, Money, HeadingDiff
client/  framework · fork · polish · cutting · stacking · delivery · main
server/  security · main · framework · cutting · stacking · delivery
```

`framework` = sessão (spawn veículo, acumula pay, paga na devolução, watchdog de
cancelamento). `fork` = operação de garfo reutilizável. Cada `cutting/stacking/delivery`
escuta `vp_lumberjack:client:jobStarted/jobEnded`.

## Dependências

`ox_lib`, `ox_target`, `ox_inventory`, `qbx_core`, `qbx_vehiclekeys`. **Sem oxmysql** (sem DB).
