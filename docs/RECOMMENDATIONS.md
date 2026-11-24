# Recomendações e próximos passos

## Decisões tomadas (e por quê)

- **Luau nativo + Lune, não roblox-ts.** O Lune roda os módulos reais fora do Roblox, no Actions, então as regras e até
  a interface são testadas sem Studio. ESLint e Prettier ficam no lugar onde fazem sentido (o app de preview em
  TypeScript); para Luau, os equivalentes são **Selene** (lint) e **StyLua** (formatação).
- **Three.js não foi usado.** O jogo é UI 2D pura dentro do Roblox, que não executa Three.js; adicioná-lo só
  aumentaria o preview sem mostrar nada mais fiel. Se um dia quiser um site/trailer com o mapa em 3D, ele cabe num
  projeto separado.
- **Sem texto livre entre jogadores** (nomes de guilda vêm de listas de palavras). O chat do Roblox (TextChatService)
  continua ativo e já é filtrado e moderado pela plataforma.
- **Sem pay-to-win.** Ouro só vem do jogo. Se for monetizar, recomendo itens cosméticos (bandeira, cor e moldura do
  castelo, temas de UI) via Developer Products, nunca tropas ou aceleração.
- **Batalhas determinísticas**, sem dados: o jogador aprende os counters e o relatório explica o resultado.

## Para lançar

1. Crie a experiência no Roblox, ative *Studio Access to API Services* e gere a chave Open Cloud com
   `universe-places: write` (secrets já cadastrados: `ROBLOX_CLOUD_API`, `ROBLOX_UNIVERSE_ID`, `ROBLOX_LOCAL_ID`).
2. Faça merge na `main`: o **Deploy** salva uma versão (*Saved*). Teste no Studio/servidor privado e rode o
   workflow manualmente com *Published* para ficar ao vivo.
3. Preencha questionário de maturidade/idade e a descrição da página do jogo.

## Próximos passos sugeridos (por impacto)

1. **Arte própria:** ícones e molduras 9-slice (ImageLabel com `SliceCenter`) no lugar dos emojis. A UI já isola tudo
   em `Components.luau`, então a troca é localizada.
2. **Reinos persistentes:** hoje o mapa e as guildas vivem enquanto o servidor vive. O próximo passo é um reino
   persistente por servidor reservado (`TeleportService:ReserveServer`) com o estado do mapa no DataStore e um
   lobby que escolhe o reino. As regras já são puras, então só a camada de servidor muda.
3. **Rally de guilda** (vários membros atacam juntos) e **eventos** (monstro chefe nas Terras da Coroa).
4. **Analytics** com `AnalyticsService` (funil das missões, tempo até Fortaleza 5) para balancear com dados.
5. **Som e animações** com `TweenService` (já há espaço no `Kit` para um prop de animação).
6. **Sorteio de reino** por nível de Fortaleza, para iniciantes não caírem com veteranos.
7. **Testes de UI** comparando screenshots entre PRs (diferença visual) usando os artefatos do CI.

## Limites conhecidos desta versão

- As screenshots são renderizadas no navegador a partir da árvore real da UI; fontes e emojis são equivalentes web.
- O mapa usa emojis como ícones; em alguns dispositivos Roblox os emojis podem aparecer com estilo do sistema.
- Guildas e mapa não persistem entre servidores (ver item 2 acima).
