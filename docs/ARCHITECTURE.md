# Arquitetura

## Princípios

1. **O servidor é dono de toda regra e todo número.** O cliente só desenha o estado e envia ordens. Cada ordem passa
   por `Protocol.validate` (tipos, inteiros, ids conhecidos, sem campos extras, sem NaN/infinito) e depois pelas
   mesmas checagens de regra que os bots usam.
2. **Regras puras.** `src/shared/Rules/*` não usa nenhuma API do Roblox, não lê relógio nem `math.random`: o tempo
   chega como `now` e a sorte vem do `Rng` com semente. Por isso o mesmo código roda no servidor e nos testes Lune,
   incluindo simulações inteiras com 50 reinos.
3. **Tempo preguiçoso.** Filas e produção são carimbos de tempo absolutos; `City.settle(data, now)` alcança o presente
   quando alguém olha. O reino cresce offline e nada "tica" por frame.
4. **Mandar só o que mudou.** O `World` marca reinos, chunks do mapa, marchas e castelos sujos; o servidor esvazia
   esses conjuntos depois de cada passo e envia cada coisa só para quem precisa.

## Fluxo de uma ordem

```
cliente: actions.upgrade("farm")
  → RemoteFunction KoR_Command("upgrade", { building = "farm" })
servidor: RateLimiter (8/s, rajada 20, por conta) → World:command(kid, …)
  → Protocol.validate → City.settle → City.startUpgrade → pedido de ajuda na guilda
  → flush(): "view" para o dono; "chunk" para quem observa o chunk; "toast"; "marches" (≤2/s)
cliente: RemoteEvent KoR_Push → Store → App.render → Kit.update (diff)
```

## 50 reinos num servidor

| Ponto | Como foi resolvido |
|---|---|
| Jogadores | `MaxPlayers` 20 (o deploy aplica via Open Cloud); 30 bots são criados no início do servidor. |
| Passo do mundo | 4× por segundo. A simulação de teste mede o passo com 50 reinos e falha se a média passar de 10 ms. |
| Bots | Cada bot age a cada 10 s, espalhados entre os passos (≈ 1 bot por passo). Usam `World.command`, a mesma porta dos jogadores. |
| Mapa | 96×96 = 9.216 tiles, mas só ≈ 580 entidades (420 campos, 110 monstros, 50 castelos). O terreno é função da semente: o cliente desenha sem rede. |
| Rede | O cliente observa só os chunks (16×16) em volta da câmera. Marchas viajam numa linha do tempo que o cliente interpola: o servidor só avisa quando uma marcha começa, muda de fase ou termina. Recursos e energia também são extrapolados no cliente a partir de taxas. |
| Interface | `Kit.memo` reaproveita a camada de terreno e de entidades enquanto a câmera não cruza um tile; só as marchas são redesenhadas a 20 fps. |

## Persistência: reinos permanentes

| Onde | Chave | O que guarda |
|---|---|---|
| DataStore `KoR_Registry_v1` | `registry` | lista de reinos: id, código do servidor reservado, PrivateServerId, membros, aberto/fechado |
| DataStore `KoR_Players_v1` | `u_<userId>` | o reino de origem do jogador |
| DataStore `KoR_Realms_v1` | `realm_<id>` | `World.snapshot`: castelos de todos os membros, bots, guildas, campos, monstros, marchas, semente e RNG |
| MemoryStore `KoR_RealmLease` | `realm_<id>` | qual servidor (JobId) está executando o reino; expira em 90 s, renovado a cada 25 s |

- **Papel do servidor** (`init.server.luau`): servidor público = lobby; servidor reservado = reino registrado para o
  seu `PrivateServerId`; servidor VIP = um reino próprio; Studio = reino local 0.
- **Lobby** (`Lobby.luau`): envia cada jogador ao reino de origem; um jogador novo recebe o reino aberto mais novo
  (`Realms.pickForNewPlayer`); se não houver, `ReserveServer` cria o próximo (`Realms.addRealm` fecha os anteriores
  para novatos).
- **Reino** (`Realm.luau`): pega a posse (`Realms.canHold`), carrega o snapshot (`World.restore` alcança o presente),
  recebe só membros (quem segue um amigo para o reino errado é levado ao seu), salva a cada 60 s e no
  `BindToClose`. Se a leitura falhar, o servidor **não** começa um reino vazio por cima: manda todos de volta ao lobby.
- **Uma só escrita:** se um segundo servidor do mesmo reino surgir (mais de 20 online), ele não ganha a posse e manda
  os jogadores para a fila do lobby. Se um servidor travar e perder a posse, para de salvar.
- **Tamanho:** bots não guardam relatórios; acima de 3,2 MB os relatórios antigos são cortados antes de salvar
  (limite do DataStore: 4 MB por chave).

## Interface

- `Kit` (diff declarativo): componentes são funções que devolvem árvores de tabelas; `Kit.update` muda só as
  propriedades e filhos que mudaram, e eventos usam um trampolim (sem reconectar a cada render).
- `Theme` escala tudo a partir de 1280×720; abaixo de 75% entra o layout compacto (celular em paisagem).
- `Live` extrapola recursos, energia e barras de progresso entre os pushes do servidor.
- Os mesmos arquivos de UI rodam no Lune com substitutos de `UDim2`, `Color3` e `Enum` para gerar as screenshots.

## Testes

| Arquivo | Cobre |
|---|---|
| `economy.spec` | custos, produção, cofre, formatação, migração de save |
| `city.spec` | filas, requisitos, armazém, treino, pesquisa, concluir com ouro, heróis, missões, cura, escudo, energia |
| `combat.spec` | vitória, counters, determinismo, perdas, muralha × cerco, enfermaria, caçada |
| `protocol.spec` | entradas de exploit (NaN, infinito, ids falsos, campos extras, negativos) |
| `world.spec` | marchas de coleta/caça/ataque, escudo de iniciante, guilda, ajuda, recuo, limites, saída, mudança de castelo, o que um jogador pode ver |
| `realms.spec` | escolha de reino, abertura do próximo, limite de membros, bots dando lugar, posse única, castelo offline atacável, salvar/carregar por JSON e alcançar 6 h depois |
| `simulation.spec` | 20 + 30 reinos jogando 2 h: invariantes (nada negativo, índices consistentes, herói em uma marcha só), custo do passo e determinismo |
| `locale.spec` | as duas línguas têm as mesmas chaves e placeholders; todo id e toda chave usada na UI tem texto |
