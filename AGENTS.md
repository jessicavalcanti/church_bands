This is a web application written using the Phoenix web framework.

## Project guidelines

- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Board do projeto

- As user stories ficam no GitHub Project **Church Bands APP** (`PVT_kwHOBXKAR84Bg25s`), do owner `jessicavalcanti`
- Cada user story é uma issue no repositório `jessicavalcanti/church_bands`, com título no formato `[US X.Y] <nome>`
- Cada user story é **sub-issue de um épico** e carrega a label da fase — o board mostra só os épicos, ver **Estrutura do board** abaixo
- Para ler uma user story: `gh issue list --repo jessicavalcanti/church_bands --state all` e depois `gh issue view <numero> --repo jessicavalcanti/church_bands`
- **Toda a especificação técnica de uma história mora no corpo da própria issue** — modelagem de dados, contratos de função, rotas, telas, autorização, cobertura e cenários de teste. Não há documento à parte: ver **A especificação técnica mora na user story** logo abaixo
- Todo card precisa carregar os PRs que o construíram, para rastrear o que entrou em cada user story. O vínculo vem da palavra-chave no corpo do PR, descrita em **Git workflow** abaixo, e é obrigatório de `Em Revisão` em diante — veja **De `Em Revisão` em diante, o card carrega o PR** logo abaixo

#### A especificação técnica mora na user story

**A issue é a fonte única.** O contexto do sistema que a história precisa
conhecer, as decisões de escopo, a modelagem das tabelas que ela cria, as regras
de negócio, os critérios de aceite, o detalhamento técnico e os cenários de teste
— automatizados e manuais — são escritos **no corpo da issue**. Quem for
implementar não precisa de mais nada além dela e do código.

**O `especificacao-tecnica.md` está obsoleto e não se atualiza mais.** Ele foi o
documento único das Fases 1 a 3 e continua na máquina como registro do que já se
decidiu, mas **nada novo entra nele**: nem história nova, nem correção de
história existente, nem fase nova. Ao refinar ou corrigir uma história, edite a
issue e só a issue.

**Por quê:** o documento e as issues carregavam o mesmo texto duas vezes, e
espelho não se mantém sozinho — bastava uma correção aplicada de um lado só para
os dois divergirem em silêncio, e quem lê a issue não tem como saber que o
documento discorda. Pior: o arquivo não é versionado (o `.gitignore` deixa passar
só `README.md` e `AGENTS.md`), então ele vive numa máquina só, enquanto a issue é
o que o time inteiro enxerga.

**Divergiu, a issue ganha.** Se o documento antigo tiver algo que a história não
tem e que ainda importa, traga o trecho para o corpo da issue — não conserte o
documento.

**Refinar uma fase nova é escrever as issues direto**, no formato que a Fase 3
usa: uma história autossuficiente por issue, na ordem da corrente de dependência,
com o "Pronto quando" fechando a lista.

#### Estrutura do board: épicos, fases e views

O board mostra **um card por épico**, não um por user story. As user stories
continuam sendo issues normais, ficam **penduradas no épico como sub-issues** e
carregam a label `user-story`, que é o que as tira das views de fase. Quem quer
ver as US abre o card do épico, ou vai na view `Todos os itens`.

Repare que são **duas coisas separadas**: pendurar no épico faz a US contar no
`Sub-issues progress`; a label `user-story` faz ela sumir do board da fase. Bug,
chore e card de débito **também** podem ser pendurados num épico — e aí contam
no progresso sem sumir do board, porque não levam a label.

Os épicos são issues comuns; o issue type nativo do GitHub não existe em conta
pessoal, então não tente usar `type:Epic`.

**O épico é da fase, não do tema.** Ele nasce com a fase, carrega **uma única
label `fase:N`** e fecha junto com ela. Uma fase tem um ou mais épicos, segundo
o que ela entrega; a fase seguinte cria os seus, mesmo que o assunto se pareça.
É o que impede o mesmo card de aparecer em duas views de fase — e de um card
fechado precisar ser reaberto para receber trabalho novo.

| Épico | Issue | Label | Fase |
|---|---|---|---|
| Acesso e Convites | #38 | `epico:acesso-e-convites` | 1 |
| Bandas e Membros | #39 | `epico:bandas-e-membros` | 1 e 2 |
| Interface | #40 | `epico:interface` | 1 |
| Repertório Musical | #41 | `epico:repertorio-musical` | 2 |
| Calendário e Escala | #65 | `epico:calendario-e-escala` | 3 |
| Set do Culto | #66 | `epico:set-do-culto` | 3 |
| Troca de Escala | #91 | `epico:troca-de-escala` | 4 |
| Notificações | #92 | `epico:notificacoes` | 4 |

**Os quatro primeiros épicos são anteriores a esta regra** e nasceram transversais —
`Bandas e Membros` chegou a atravessar duas fases, o que é justamente o que a
regra nova evita. Eles ficam como estão: reescrevê-los mudaria o histórico do
board sem melhorar nada. A regra vale **da Fase 3 em diante**, e os dois épicos
da Fase 3 já nasceram assim.

##### Ao criar uma user story

Três passos, nenhum opcional — pular qualquer um deles deixa o card fora da view
da fase, ou solto como card próprio quando não deveria:

1. **Labels:** a `epico:<tema>` do épico dela, a `fase:N` da fase **e a `user-story`**
2. **Pendurar no épico:** `gh issue edit <épico> --add-sub-issue <US>`
3. **Adicionar ao projeto:** `gh project item-add 2 --owner jessicavalcanti --url <url da issue>`

A `user-story` é a label que **esconde** a US da view da fase — é ela, e não a
relação pai-filho, que enxuga o board (ver **Views por fase**). US sem essa
label aparece como card próprio ao lado dos épicos.

**A label `epico:<tema>` não pendura nada.** Ela filtra e identifica o tema;
quem alimenta o `Sub-issues progress` do épico é só a relação pai-filho do
passo 2. Issue com a label e sem pai não entra na conta — e o épico chega a
marcar 100% com trabalho aberto do tema, que é o board mentindo pelo pior
motivo: parece certo. Vale igual para **bug e chore**, que não passam por este
checklist: se pertencem a um tema, pendure no épico (ver **Views por fase**);
se são trabalho avulso, deixe soltos com a `fase:N`. Para achar quem ficou pelo
caminho:

    gh api graphql -f query='{repository(owner:"jessicavalcanti",name:"church_bands"){issues(first:60,states:[OPEN,CLOSED]){nodes{number title labels(first:10){nodes{name}} parent{number}}}}}'

Os próprios épicos aparecem nessa lista sem pai, e é assim mesmo — eles carregam
a label do tema que representam.

**Épico de fase nova se cria, não se reabre.** Como o épico é da fase, a
primeira user story de uma fase encontra o épico dela recém-criado e aberto —
não há label de fase para acrescentar num card antigo, nem card fechado para
reabrir. Os dois cuidados abaixo valem **só para os quatro épicos transversais
da tabela acima**, se algum dia voltarem a receber trabalho:

- acrescente a `fase:N` ao épico: `gh issue edit <épico> --add-label "fase:N"`
- reabra o épico se ele estiver fechado: `gh issue reopen <épico>`. O GitHub
  fecha o pai sozinho quando todas as sub-issues fecham, então um épico de tema
  já entregue chega na fase seguinte fechado

##### Views por fase

| View | Filtro | Para quê |
|---|---|---|
| `Todos os itens` | — | tudo, inclusive as user stories |
| `Épicos — Fase 1` | `label:"fase:1" -label:"user-story"` | board enxuto da fase |
| `Épicos — Fase 2` | `label:"fase:2" -label:"user-story"` | idem |
| `Épicos — Fase 3` | `label:"fase:3" -label:"user-story"` | idem |
| `Épicos — Fase 4` | `label:"fase:4" -label:"user-story"` | idem |

**O filtro esconde por label, não por parentesco.** A primeira versão usava
`no:parent-issue`, e isso criava um dilema sem saída: pendurar um bug no épico
para ele contar no `Sub-issues progress` fazia o card **sumir** da view da fase,
e deixá-lo solto para aparecer no board tirava-o da conta do épico. Nenhum dos
dois era aceitável — um bug aberto precisa das duas coisas.

Trocando para `-label:"user-story"`, quem some da view é só a user story, que é
o que realmente enche o board. Bug, chore e card de débito continuam visíveis
como cards próprios **e** podem estar pendurados no épico, contando no
progresso. É por isso que a `user-story` existe como label: não é decoração, é o
que o filtro lê.

Continua valendo: item sem a `fase:N` não aparece em view nenhuma.

Cada fase nova precisa da sua view. São duas chamadas, porque
`createProjectV2View` **não aceita `filter`**:

    gh api graphql -f query='mutation{createProjectV2View(input:{projectId:"PVT_kwHOBXKAR84Bg25s",name:"Épicos — Fase 3",layout:BOARD_LAYOUT}){projectV2View{id number}}}'

    gh api graphql -f query='mutation($v:ID!,$f:String!){updateProjectV2View(input:{viewId:$v,filter:$f,configuration:{visibleFieldIds:["PVTF_lAHOBXKAR84Bg25szhf0334","PVTF_lAHOBXKAR84Bg25szhf034E","PVTF_lAHOBXKAR84Bg25szhf034I","PVTF_lAHOBXKAR84Bg25szhf034g"]}}){projectV2View{number name filter}}}' -f v='<VIEW_ID>' -f f='label:"fase:3" -label:"user-story"'

Os quatro `visibleFieldIds` são `Title`, `Labels`, `Linked pull requests` e
`Sub-issues progress`. A barra de progresso é o que faz o card do épico valer
como resumo da fase; `Linked pull requests` é o que mostra **na capa do card** o
número do PR e o estado dele, sem precisar abrir o card. **Não corte esse
campo de uma view nova:** o vínculo continua existindo sem ele, mas some da
vista, e o board volta a parecer que a issue não tem PR. Para conferir as views
existentes, com os campos visíveis de cada uma:

    gh api graphql -f query='{user(login:"jessicavalcanti"){projectV2(number:2){views(first:10){nodes{number name filter fields(first:20){nodes{... on ProjectV2FieldCommon{name}}}}}}}}'

A API devolve o filtro **gravado**, nunca o resultado dele: não existe forma de
listar por API os cards que uma view mostra. Ao mexer em view, confira o
resultado pela interface antes de dar por feito.

##### Status do épico

O épico não anda pela tabela de status da seção seguinte — essa é da user story.
Ele reflete o conjunto: `Em Desenvolvimento` enquanto houver sub-issue aberta da
fase corrente, `Concluída` quando o `Sub-issues progress` do card fechar. Não
mova o épico ao começar uma US; mova a US.

**O fechamento automático do pai demora, e a demora vai de minutos a quase um
dia.** O GitHub fecha mesmo a issue-pai quando a última sub-issue fecha, mas de
forma assíncrona e sem cadência garantida. Os casos medidos:

| Última sub-issue | Épico | Demora |
|---|---|---|
| US 3.5 (#71) | #65 | 3 minutos |
| US 3.7 (#73) | #66 | ~14 horas |
| US 2.8 (#54) | #41 | ~20 horas |

Nesse intervalo o épico aparece com o `Sub-issues progress` cheio **e** estado
`OPEN`, e o card fica no status anterior — é o board parecendo atrasado sem
estar quebrado. Como no `Linked pull requests`, **consulte de novo antes** de
concluir que o automatismo falhou; ao contrário dele, aqui "de novo" pode ser no
dia seguinte, e não daqui a um minuto.

**Não feche o épico à mão** enquanto a demora couber nessa faixa — é como se
acaba escrevendo um comentário explicando um problema que não existe. Fechar à
mão também apaga a única evidência de que o automatismo falhou, no dia em que
ele falhar de verdade.

#### Status do card acompanha o trabalho

O board é onde se lê o andamento do projeto sem abrir o código. **Mover o card faz parte da tarefa, não é burocracia depois dela:** um card parado em `Backlog` enquanto a história já está implementada faz o board mentir sobre o que está acontecendo.

Atualize o status **no momento** em que a ação acontece, nunca em lote no fim:

| Quando | Status |
|---|---|
| Ao começar a implementar (criar a branch da user story) | `Em Desenvolvimento` |
| Ao abrir o Pull Request | `Em Revisão` |
| Depois do merge na `develop` | `Concluída` — **automático**, ver abaixo |
| Ao gravar a demonstração da história | `Demonstrada (vídeo)` |

`Pronta para Dev` é decisão de refinamento, definida por quem prioriza — não mexa nela.

##### De `Em Revisão` em diante, o card carrega o PR

**Toda issue em `Em Revisão`, `Concluída` ou `Demonstrada (vídeo)` precisa ter ao
menos um Pull Request associado.** É o PR que prova o que construiu a história:
card nessas colunas sem PR não dá para auditar — não se sabe qual código
entregou aquilo nem em que release ele foi parar. Se o card avançou e não há PR,
ou o status subiu cedo demais, ou o vínculo falhou.

A associação **não se faz na mão**. Ela vem da palavra-chave `Closes #<numero>`
no corpo do PR (veja **Git workflow**), e o GitHub preenche sozinho o campo
`Linked pull requests` do card. Campo vazio quer dizer que a palavra-chave não
pegou — lembrando que `Fecha` e `Encerra` **não** são reconhecidas —, e o
conserto é editar o corpo do PR, nunca mexer no board.

Para varrer todos os cards de uma vez:

    gh api graphql -f query='{node(id:"PVT_kwHOBXKAR84Bg25s"){... on ProjectV2{items(first:60){nodes{content{... on Issue{number}} status:fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}} prs:fieldValueByName(name:"Linked pull requests"){... on ProjectV2ItemFieldPullRequestValue{pullRequests(first:5){nodes{number state}}}}}}}}}'

O campo é preenchido de forma assíncrona e leva alguns segundos depois que o PR
abre. Se o PR acabou de sair, **consulte de novo antes** de concluir que o
vínculo falhou.

Card que não mostra o PR na capa também pode ser view mal configurada, e não
vínculo quebrado: `Linked pull requests` só aparece na capa se estiver entre os
campos visíveis daquela view (ver **Views por fase**). Antes de investigar a
palavra-chave, confira o campo pela query acima — ela lê o vínculo direto do
card, independentemente de qual view está aberta.

**A única exceção é o épico**, que é issue-pai: ele fecha quando suas sub-issues
fecham e nunca tem PR próprio (veja **Status do épico** acima). Todo o resto —
user story, bug, chore e card de débito técnico — passa por PR e precisa
carregá-lo.

##### `Concluída` é o único status automático

O workflow **Item closed** do Project move o card para `Concluída` sozinho. A
corrente é: o PR traz `Closes #<numero>` → o merge fecha a issue → o workflow vê
a issue fechada e muda o status. Depois do merge, **confira** o status em vez de
defini-lo; se o card não andou, o elo que falhou é quase sempre a palavra-chave
do PR (veja **Git workflow**), não o workflow.

Os outros dois workflows do board induzem ao erro e vale saber por quê:

- **Pull request merged** age no card do *próprio pull request*, não na issue que
  ele fecha. O board só tem issues como itens, então esse workflow dispara e não
  encontra nada para mover — parece quebrado, e está funcionando como projetado
- **Item closed** dispara em *qualquer* fechamento, inclusive `not planned`. Uma
  história cancelada vai parar em `Concluída` — ao cancelar um card, corrija o
  status na mão depois de fechar a issue

A configuração dos workflows não é exposta na API do GitHub (só existe
`deleteProjectV2Workflow`, e `ProjectV2Workflow` devolve apenas `name`, `enabled`
e `number`). Para ler ou mudar como estão, é pela interface: no board, `⋯` →
**Workflows**. Dá para conferir quais estão ligados assim:

    gh api graphql -f query='{node(id:"PVT_kwHOBXKAR84Bg25s"){... on ProjectV2{workflows(first:20){nodes{name enabled}}}}}'

O campo `Status` é um single select do Project (`PVTSSF_lAHOBXKAR84Bg25szhf034A`). Para descobrir o id do card e os ids das opções:

    gh api graphql -f query='{node(id:"PVT_kwHOBXKAR84Bg25s"){... on ProjectV2{items(first:50){nodes{id content{... on Issue{number}} fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}'

e para mover o card:

    gh api graphql -f query='mutation{updateProjectV2ItemFieldValue(input:{projectId:"PVT_kwHOBXKAR84Bg25s",itemId:"<ITEM_ID>",fieldId:"PVTSSF_lAHOBXKAR84Bg25szhf034A",value:{singleSelectOptionId:"<OPTION_ID>"}}){projectV2Item{id}}}'

Confirme o novo status na resposta da mutation — ela devolve o card atualizado, e é a única forma de saber que o board mudou de verdade.


### Débitos técnicos

**Um card por fase**, para que o card feche quando a fase fecha. Hoje existem
**#11 — Fase 1** (fechado), **#30 — Fase 2**, **#74 — Fase 3** (fechado) e
**#93 — Fase 4**.

Achar o card da fase em que você está trabalhando é o primeiro passo antes de
registrar qualquer débito — nunca escreva num card de outra fase, e nunca confie
na lista acima sem conferir:

    gh issue list --repo jessicavalcanti/church_bands --label debito-tecnico --state all

Os títulos seguem `[Débito Técnico] Fase N — <nome da fase>`, os mesmos nomes de
fase do `ideias-fases-2-3-4.md`. **Todas as quatro fases já têm card**, porque
todas já foram refinadas — o da Fase 4 nasceu com o refinamento dela. O card é
criado quando a fase vira user stories, não antes: o board não carrega card
vazio de trabalho que ainda não existe. Se você chegar a uma fase sem card,
**pergunte antes de criar**: criar o card é decisão de quem prioriza, e nasce
junto com o refinamento da fase.

Regras que valem para todos os cards:

- **O card leva a label `fase:N` da sua fase**, além de `debito-tecnico`. Ele não
  tem épico e fica solto no board — é a label de fase que o coloca na view
  `Épicos — Fase N`, e sem ela o card não aparece em view nenhuma
- **Um débito fica no card da fase em que nasceu**, mesmo que só seja resolvido
  depois. É assim que dá para enxergar o que cada fase deixou para trás — e por
  isso um débito **nunca muda de card**
- **A numeração `DT-N` é contínua no projeto inteiro**, não reinicia a cada
  fase. O código e as mensagens de commit citam `DT-1`, `DT-4` e `DT-9`
  diretamente, e um segundo `DT-1` na Fase 2 tornaria essas referências
  ambíguas. **A Fase 2 começa em `DT-12`.** Ids de itens resolvidos não são
  reaproveitados
- **Ao resolver:** marque a caixa, risque o texto e anote o PR que resolveu
- **O card fecha pelo `Closes` do PR que zerar o último item.** Enquanto sobrar
  item aberto o card fica aberto, mesmo que a fase já tenha fechado — card
  fechado com item pendente faz o board mentir
- **Antes de todo merge `develop` → `main`**, leia o card da fase inteiro, junto
  com o roteiro de testes. Todo item marcado como `bloqueia entrega` precisa
  estar resolvido

O status do card segue a mesma tabela das user stories, com um detalhe próprio:
ele **fica em `Backlog` enquanto só acumula itens** — acrescentar um `DT-N` não
é começar a trabalhar nele. Só vai para `Em Revisão` quando existir um PR aberto
que o zera, e daí para `Concluída` sozinho, pelo `Closes` desse PR.

### Roteiro de testes

- `roteiro-de-testes.html`, na raiz do projeto, é o roteiro de **validação manual**: uma página HTML interativa com o que percorrer na aplicação rodando para confirmar cada funcionalidade entregue. É um documento autocontido — sem build, sem dependência externa além da fonte do Google Fonts — que se abre direto no navegador
- **Toda funcionalidade entregue precisa entrar nesse documento, no mesmo PR que a entrega** — uma user story só está concluída quando o roteiro cobre o que ela passou a fazer. Vale para funcionalidade nova e para mudança de comportamento de uma já existente
- Cada cenário é um cartão `.case` com id (`1.4-B`), o perfil necessário (`.as`), os passos numerados e um bloco de resultado: `.expect` para o que deve acontecer, `.expect.deny` para o que deve ser recusado. As **recusas de permissão** são cenário de primeira classe: a regra do sistema é *leitura ampla, escrita restrita*, então forçar a URL na mão faz parte do teste
- Mantenha o padrão visual e a estrutura já existentes ao acrescentar uma seção — a página tem identidade própria e não deve ser redesenhada a cada entrega. Atualize junto: a navegação do topo, a **matriz de permissões** e o rodapé
- Ao mudar mensagens de tela, textos de flash ou rotas, revise o roteiro junto — ele cita essas mensagens literalmente, entre `<q>`
- **O roteiro cobre todos os cenários de teste manual possíveis da funcionalidade entregue**, inclusive os que a suíte automatizada já verifica — existir teste unitário não dispensa o cenário do roteiro. Ele é a validação manual completa da entrega, e não só o resto que a suíte não alcança (o e-mail que chega, o link que abre, o botão que aparece para um perfil e some para outro)
- **Só o arquivo local `roteiro-de-testes.html` precisa ser atualizado.** A entrega termina no arquivo versionado no repositório — não é preciso republicar o roteiro como Artifact nem manter nenhuma cópia publicada em dia
- O roteiro é lido inteiro antes de cada merge `develop` → `main`, junto com o card de débito técnico da fase (ver **Débitos técnicos** acima)

### Cobertura de testes

- A cobertura é medida pela `excoveralls` e o mínimo é **100%**, configurado em `coveralls.json`. `mix precommit` roda `mix coveralls` no lugar de `mix test`, então o CI reprova o PR que baixar a cobertura — a suíte roda uma vez só, e o veredito é o mesmo na máquina de quem desenvolve e no CI
- Para ver o que falta, `mix coveralls.detail --filter <arquivo>` mostra o código linha a linha, com as não exercitadas em vermelho; `mix coveralls.html` gera `cover/excoveralls.html`
- **O nome do teste diz o que ele testa, nunca que ele existe para cobrir uma linha.** "reenviar um convite já aceito é recusado, mesmo forçando o evento" — não "cobre o ramo `:already_accepted`". Se não der para nomear assim, provavelmente o que falta é entender o comportamento, e não escrever o teste
- **Todo componente instalado conta na medição.** Os que nenhuma tela usava foram apagados na revisão de fechamento da Fase 1 (R-16) em vez de ficarem listados como exceção, então o `skip_files` do `coveralls.json` guarda só duas peças de base do SaladUI, que não são componentes: `components/ui.ex` (o `use ..., :component`, que é macro e não executa) e `components/ui/live_view.ex` (a ponte `send_command/4` que `sheet` e `tooltip` documentam). Componente reposto depois **não** entra nessa lista: nasce medido como qualquer outro código, inclusive os usados indiretamente, como `sheet` e `tooltip` por dentro de `sidebar`, e inclusive a parte que nenhuma tela chama ainda — foi o que o `toast` custou em `toast_test.exs`
- **Linha que não tem como ser exercitada leva `# coveralls-ignore-next-line` (ou `-start`/`-stop`) e um comentário dizendo por quê.** São poucas e todas do mesmo tipo: o ramo de erro que um `case` sobre `Repo.transaction/1` precisa ter para não estourar, mas que nenhum caminho do código alcança. Marcar assim é diferente de baixar o mínimo: a exceção fica visível, nomeada e revisável no diff
- Cobertura de 100% não quer dizer suíte completa — quer dizer que nenhuma linha passou sem ser executada. O que garante que ela foi executada **pelo motivo certo** continua sendo o teste ter sido escrito a partir do comportamento

### Git workflow

- The default branch is `develop`. `main` holds only validated releases
- **Never** commit or push directly to `main` or `develop` — both are protected and the push will be rejected. Every change goes through a Pull Request
- Create one branch per user story, from `develop`, named `feat/us-X.Y-<short-slug>` (for example `feat/us-1.2-account-activation-login`)
- Open Pull Requests against `develop`. Only the release merge (`develop` → `main`) targets `main`
- Before opening or updating a PR, sync with the base: `git fetch origin && git rebase origin/develop`
- **Every PR must link its user story issue**, so the board card records which PRs built it. Put a closing keyword on the first line of the PR body: `Closes #<numero>`, one line per issue when the PR closes more than one
- The keyword **must be in English** — `Closes`, `Fixes` or `Resolves`. Portuguese words like `Fecha` and `Encerra` are **not** recognized by GitHub: the PR becomes a plain mention, the issue stays open after the merge and the card ends up with no PR attached. Only the keyword is in English; the rest of the PR body stays in Portuguese
- Confirm the link before merging — an empty list means the keyword did not work and the card will not get its PR:

      gh api graphql -f query='{repository(owner:"jessicavalcanti",name:"church_bands"){pullRequest(number:PR){closingIssuesReferences(first:5){nodes{number}}}}}'

- **Todo PR é verificado pelo CI** (`.github/workflows/ci.yml`), que roda o mesmo
  `mix precommit` com um PostgreSQL de serviço e depois confere que a árvore
  ficou limpa (`git diff --exit-code`) — `precommit` roda `format` e
  `deps.unlock --unused`, que **corrigem** em vez de reclamar, e sem essa
  conferência um PR mal formatado passaria batido. O alias do `mix.exs` é a
  definição única do que precisa passar; não duplique a lista no workflow
- A closing keyword only fires **at merge time**. Fixing the body of an already merged PR restores the link on the card, but the issue has to be closed by hand

### Releases e versões

Todo merge `develop` → `main` é uma release, e cada uma vira uma **versão que dá
para rodar de novo depois** — é o que permite gravar a demonstração de uma fase
sem a fase seguinte por cima.

- **A versão é a do `mix.exs`**, e é a fonte única. O **PR de release sobe o
  `version:`** como parte da entrega; não existe tag digitada à parte
- `.github/workflows/release.yml` é o par disso: **recusa antes do merge** o PR
  para a `main` cujo número já tenha sido publicado — que é o que acontece quando
  alguém esquece de subir a versão — e, depois do merge, cria a tag `vX.Y.Z` e
  publica a release com as notas geradas a partir dos PRs. As notas trazem o
  comando de rodar aquela versão
- **Uma versão menor por fase** — `v0.1.0` é a Fase 1, `v0.2.0` a Fase 2, e
  `v1.0.0` só quando as quatro estiverem entregues. Correção sobre uma fase já
  publicada sobe o terceiro número
- **Para rodar uma versão antiga, use `git worktree`**, nunca `git checkout` no
  diretório de trabalho: o compose monta a árvore dentro do container, então
  trocar de tag ali mudaria o código do ambiente de desenvolvimento junto. O
  `APP_PORT` do `docker-compose.yml` existe para essa segunda instância subir em
  outra porta. A receita completa está no `README.md`

### Pontos de decisão em aberto

Uma implementação quase nunca termina limpa. Sobra alguma coisa: um campo que a
especificação não previu, uma escolha de escopo feita no caminho, uma lacuna que
só ficou visível depois do código pronto. **Esses pontos não podem terminar como
um parágrafo no fim da resposta.** Enterrado no meio de um relatório de entrega,
o ponto é lido, parece razoável e nunca vira decisão — e na entrega seguinte
ninguém lembra que existiu.

Ao terminar a implementação, se restar **qualquer ponto que dependa de uma
decisão de quem prioriza**, abra uma sessão interativa de perguntas e respostas
(a ferramenta `AskUserQuestion`) antes de encerrar o trabalho. Uma pergunta por
ponto em aberto, com as opções que realmente existem:

| Opção | O que significa |
|---|---|
| **Corrigir agora** | Entra neste mesmo PR, antes do merge |
| **Débito técnico** | Vira item `DT-N` no card de débito técnico **da fase em que nasceu** |
| **Card novo** | Vira uma user story própria no board, para ser priorizada |
| **Ignorar** | Decisão consciente de não fazer — e o ponto morre aqui |

Regras da sessão:

- **Pergunte no fim, não durante.** Só interrompa a implementação se avançar sem
  a resposta tornaria o trabalho inútil ou inseguro. Fora isso, entregue tudo o
  que não depende da decisão e traga a pergunta depois, com o código pronto na
  mão — é mais fácil decidir olhando o que existe do que no abstrato
- **Uma pergunta é sobre uma decisão, não sobre uma preferência.** Se o ponto tem
  um padrão óbvio, escolha o padrão, diga qual escolheu e siga. A sessão é para o
  que muda o produto, não para o que muda de cor
- **Recomende.** Coloque a opção que você recomenda em primeiro lugar, marcada
  com `(Recomendado)`, e diga por quê na descrição. Chegar com quatro opções
  equivalentes empurra o trabalho de volta para quem perguntou
- **Execute a resposta na hora.** Escolheu débito técnico, o item `DT-N` é criado
  no card da fase na mesma sessão; escolheu corrigir, o commit entra no PR;
  escolheu card novo, a issue é aberta. Uma decisão tomada e não registrada é
  igual a não ter perguntado
- **O PR registra o resultado**, não a dúvida. Se o ponto virou débito, o corpo
  do PR cita o `DT-N`; se foi ignorado, diz que foi decisão consciente e por quê

Isso vale também para o que você **descobre** sem que ninguém tenha pedido: um
bug encontrado de passagem, um débito que a história ao lado deixou, uma
inconsistência entre a especificação e o código. Mesmo tratamento — pergunte,
decida, registre.

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `MyAppWeb.Layouts` module is aliased in the `my_app_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs — desde a US 1.9 ele vem do SaladUI, não do `core_components.ex`. Ver **Design system** abaixo
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
custom classes must fully style the input

### Design system

A base visual é o [SaladUI](https://hexdocs.pm/salad_ui) v1.0, port do shadcn/ui
para LiveView, instalado com `mix salad.install --prefix ChurchBandsWeb.Components.UI --color-scheme neutral`.
Como no shadcn, **os componentes são do projeto**: foram copiados para
`lib/church_bands_web/components/ui/` e podem ser editados. Onde um deles já foi
ajustado, o comentário começa com "Ajuste local (US X.Y)" — siga esse padrão ao
mexer neles, e prefira ajustar a peça a inventar uma paralela.

Por isso a dependência `salad_ui` é `only: :dev, runtime: false`: nada em runtime
referencia o módulo `SaladUI`, e deixá-la em produção arrastaria o `igniter` e
mais cinco pacotes de ferramenta de código para dentro do release. A de runtime é
o `tw_merge`, que resolve as classes de todo componente. Se rodar o instalador de
novo, confira o `mix.exs` depois — ele volta a declarar `salad_ui` em produção.

- **Componente que o SaladUI tem, vem do SaladUI.** `button`, `input`,
  `textarea`, `label`, `badge`, `card`, `alert`, `avatar`, `separator`,
  `tooltip`, `sheet`, `dropdown_menu`, `sidebar`, `breadcrumb`, `toast` e os
  `form_item` / `form_label` / `form_description` / `form_message`. Os de uso
  geral já estão importados em `church_bands_web.ex`; os da moldura, em
  `layouts.ex`
- **A mensagem de `put_flash/3` aparece como toast.** Quem a desenha é o
  `<.toaster flash={@flash} />` que `flash_group/1` monta uma vez por página
  (#87): a ponte do componente converte cada flash em toast e limpa o flash no
  servidor no mesmo passo, então **as telas continuam chamando `put_flash/3`** —
  não há API nova para aprender. `put_toast/4` e os `toast_*` existem para o
  aviso que não vem de flash, e ainda não têm chamador. Os dois avisos de
  conexão (`#client-error` e `#server-error`) **não** são toast: são estado, e
  continuam no `<.flash>` sobre o `alert`
- **Só os componentes em uso estão instalados.** O instalador copiou 41 e a
  Fase 1 usa 18; os outros 22 foram apagados na revisão de fechamento da fase
  (R-16), porque eram 33% de todo o `lib/` que nenhuma tela chamava.
  **Precisou de um deles?** A v1.0 do SaladUI **não tem `mix salad.add`**, e
  rodar `mix salad.install` de novo traria os 22 de volta. Repor é copiar
  `deps/salad_ui/lib/salad_ui/<componente>.ex` para `components/ui/` trocando
  `SaladUI` pelo prefixo do projeto, como o instalador faz — o passo a passo
  está no `@moduledoc` de `components/ui.ex`. O componente vale como código do
  projeto: entra na medição de cobertura, e o `import` correspondente entra na
  lista de `components/ui.ex`. Junto vem o JavaScript dele, que precisa de um
  `import` em `assets/js/app.js` para ser registrado (ver `dialog`,
  `dropdown_menu`, `tooltip` e `toast` lá)
- **`core_components.ex` guarda só o que é do projeto:** `header/1`, `icon/1`,
  `select/1` (um `<select>` nativo — o do SaladUI é uma lista em JavaScript, que
  não submete sozinha nem dá para dirigir por teste) e `table/1` (a tabela com
  slots `:col`/`:action` e stream, montada sobre as peças de tabela do SaladUI).
  `SaladUI.Table` fica **fora** dos imports de propósito, para não colidir com
  esses quatro; `SaladUI.Icon` e `SaladUI.Select`, que colidiriam do mesmo
  jeito, não estão mais instalados (R-16)
- **Campo de formulário é sempre o trio** rótulo, campo e mensagem dentro de um
  `<.form_item>`:

      <.form_item>
        <.form_label field={@form[:email]}>E-mail</.form_label>
        <.input field={@form[:email]} type="email" required />
        <.form_message field={@form[:email]} />
      </.form_item>

- **Botão que navega é `<.link>` com as classes de botão**, como no shadcn —
  `<.link navigate={~p"/bands"} class={button_variant(%{variant: "outline"})}>`.
  O `<.button>` do SaladUI é só `<button>`
- **A paleta é preto e branco**, o esquema `neutral` do shadcn, em
  `assets/css/app.css`. Use os tokens (`bg-background`, `text-foreground`,
  `text-muted-foreground`, `border-border`, `bg-muted`, `bg-sidebar`…), **nunca
  uma cor literal**. `destructive` (vermelho) é a única cor que sobrou, e vale
  só para excluir e remover
- **Modo escuro é a classe `.dark` no `<html>`**, posta pelo script do
  `root.html.heex`. Os três estados — sistema, claro, escuro — e a persistência
  em `localStorage` continuam valendo

### Moldura das telas

Duas molduras, ambas em `layouts.ex`:

- `<Layouts.app>` — o portal de quem está logado. Recebe `flash`,
  `current_user`, `current_path` (para destacar o item do menu) e `breadcrumb`.
  Tem um slot `:actions` para os botões de ação da tela, que ficam na faixa
  superior, junto do breadcrumb. O `<.header>` da tela leva só título e
  subtítulo
- `<Layouts.public>` — login, ativação de conta, recuperação de senha e a
  vitrine de `/` para visitante. Sem barra lateral e sem breadcrumb

O **breadcrumb é montado por assign**, nunca lido da URL: é assim que `:id` vira
o nome da banda ou da pessoa. Uma lista de `{rótulo, caminho}` a partir de
*Início* (que o layout acrescenta sozinho), com o último item sem caminho:

    breadcrumb={[{"Bandas", ~p"/bands"}, {@band.name, nil}]}

**Esconder um item do menu não é autorização.** O menu mostra o que a pessoa
pode acessar porque oferecer um caminho que termina em recusa é um mau portal —
quem protege continua sendo o hook da `live_session` no router.

### Idioma da interface

A aplicação fala **português do Brasil**, e isso está configurado — não é só uma
convenção de quem escreve texto. `ChurchBandsWeb.Gettext` tem
`default_locale: "pt_BR"` e `allowed_locales: ~w(pt_BR)`, e as traduções vivem em
`priv/gettext/pt_BR/LC_MESSAGES/`. `en` foi removido de propósito: um locale só,
sem tradução paralela para envelhecer.

São duas camadas, e cada uma tem o seu lugar:

- **A mensagem escrita à mão, no `message:` da validação**, é a que diz algo que
  o padrão não diria: `"informe o nome da banda"`, `"escolha o naipe"`,
  `"precisa conter ao menos um número"`. Use sempre que a regra tiver nome
  próprio no domínio
- **A tradução do gettext é a rede de proteção.** Validação sem `message:` cai no
  texto padrão do Ecto, que é em inglês — `errors.po` devolve isso em português
  (`"não pode ficar em branco"`, `"precisa ter ao menos %{count} caracteres"`).
  A redação segue a voz dos `message:` escritos à mão, para que as duas camadas
  soem como a mesma aplicação

Ao acrescentar texto novo que passe pelo `gettext/1` do layout, rode
`mix gettext.extract --merge` e preencha o `msgstr` em
`priv/gettext/pt_BR/LC_MESSAGES/default.po` — um `msgstr` vazio cai de volta no
inglês do `msgid`. **Mensagem em inglês na tela é defeito**, e o roteiro de
testes pede que quem valida à mão anote em qual campo apareceu.

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/my_app_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Never** use daisyUI: ela saiu na US 1.9 e não convive com o SaladUI — os dois
  definem `--color-accent`. Classe `btn`, `navbar`, `badge-primary`, `card`,
  `base-100/200/300`, `text-base-content`, `link` e `divide-base-300` não existem
  mais aqui
- **Nunca** use `@plugin "@tailwindcss/typography"`: o projeto não tem
  `node_modules`, e o plugin quebra o build. O instalador do SaladUI escreve
  essa linha — apague-a se rodar o instalador de novo
- Out of the box **only the app.js and app.css bundles are supported**
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**
  - A única exceção ao "sem `href` externo no layout" é a fonte **Geist**, que o
    `root.html.heex` carrega do Google Fonts por `<link>`, com pilha de fallback
    declarada em `--font-sans`
- Hook de JavaScript próprio mora em `assets/js/hooks/` e é registrado em
  `app.js`, ao lado do hook `SaladUI`

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions


<!-- usage-rules-start -->

<!-- phoenix:elixir-start -->
## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you *must* bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: MyApp.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(MyApp.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests as it guarantees cleanup between tests
- **Avoid** `Process.sleep/1` and `Process.alive?/1` in tests
  - Instead of sleeping to wait for a process to finish, **always** use `Process.monitor/1` and assert on the DOWN message:

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

   - Instead of sleeping to synchronize before the next call, **always** use `_ = :sys.get_state/1` to ensure the process has handled prior messages
<!-- phoenix:elixir-end -->

<!-- phoenix:phoenix-start -->
## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it
<!-- phoenix:phoenix-end -->

<!-- phoenix:ecto-start -->
## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programmatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct
- **Always** invoke `mix ecto.gen.migration migration_name_using_underscores` when generating migration files, so the correct timestamp and conventions are applied
<!-- phoenix:ecto-end -->

<!-- phoenix:html-start -->
## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `my_app_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use MyAppWeb, :html` (replace "my_app" by the actual app name)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`**. **Never use `else if` or `elseif` in Elixir**, **always** use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you *must* annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>
<!-- phoenix:html-end -->

<!-- phoenix:liveview-start -->
## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and  `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:
  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are *not* enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
         socket
         |> assign(:messages_empty?, messages == [])
         # reset the stream with the new messages
         |> stream(:messages, messages, reset: true)}
      end

- LiveView streams *do not support counting or empty states*. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @streams.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- When updating an assign that should change content inside any streamed item(s), you MUST re-stream the items
  along with the updated assign:

      def handle_event("edit_message", %{"message_id" => message_id}, socket) do
        message = Chat.get_message!(message_id)
        edit_form = to_form(Chat.change_message(message, %{content: message.content}))

        # re-insert message so @editing_message_id toggle logic takes effect for that stream item
        {:noreply,
         socket
         |> stream_insert(:messages, message)
         |> assign(:editing_message_id, String.to_integer(message_id))
         |> assign(:edit_form, edit_form)}
      end

  And in the template:

      <div id="messages" phx-update="stream">
        <div :for={{id, message} <- @streams.messages} id={id} class="flex group">
          {message.username}
          <%= if @editing_message_id == message.id do %>
            <%!-- Edit mode --%>
            <.form for={@edit_form} id="edit-form-#{message.id}" phx-submit="save_edit">
              ...
            </.form>
          <% end %>
        </div>
      </div>

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView JavaScript interop

- Remember anytime you use `phx-hook="MyHook"` and that JS hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Always** provide an unique DOM id alongside `phx-hook` otherwise a compiler error will be raised

LiveView hooks come in two flavors, 1) colocated js hooks for "inline" scripts defined inside HEEx,
and 2) external `phx-hook` annotations where JavaScript object literals are defined and passed to the `LiveSocket` constructor.

#### Inline colocated js hooks

**Never** write raw embedded `<script>` tags in heex as they are incompatible with LiveView.
Instead, **always use a colocated js hook script tag (`:type={Phoenix.LiveView.ColocatedHook}`)
when writing scripts inside the template**:

    <input type="text" name="user[phone_number]" id="user-phone-number" phx-hook=".PhoneNumber" />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PhoneNumber">
      export default {
        mounted() {
          this.el.addEventListener("input", e => {
            let match = this.el.value.replace(/\D/g, "").match(/^(\d{3})(\d{3})(\d{4})$/)
            if(match) {
              this.el.value = `${match[1]}-${match[2]}-${match[3]}`
            }
          })
        }
      }
    </script>

- colocated hooks are automatically integrated into the app.js bundle
- colocated hooks names **MUST ALWAYS** start with a `.` prefix, i.e. `.PhoneNumber`

#### External phx-hook

External JS hooks (`<div id="myhook" phx-hook="MyHook">`) must be placed in `assets/js/` and passed to the
LiveSocket constructor:

    const MyHook = {
      mounted() { ... }
    }
    let liveSocket = new LiveSocket("/live", Socket, {
      hooks: { MyHook }
    });

#### Pushing events between client and server

Use LiveView's `push_event/3` when you need to push events/data to the client for a phx-hook to handle.
**Always** return or rebind the socket on `push_event/3` when pushing events:

    # re-bind socket so we maintain event state to be pushed
    socket = push_event(socket, "my_event", %{...})

    # or return the modified socket directly:
    def handle_event("some_event", _, socket) do
      {:noreply, push_event(socket, "my_event", %{...})}
    end

Pushed events can then be picked up in a JS hook with `this.handleEvent`:

    mounted() {
      this.handleEvent("my_event", data => console.log("from server:", data));
    }

Clients can also push an event to the server and receive a reply with `this.pushEvent`:

    mounted() {
      this.el.addEventListener("click", e => {
        this.pushEvent("my_event", { one: 1 }, reply => console.log("got reply from server:", reply));
      })
    }

Where the server handled it via:

    def handle_event("my_event", %{"one" => 1}, socket) do
      {:reply, %{two: 2}, socket}
    end

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule MyApp.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %MyApp.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset
<!-- phoenix:liveview-end -->

<!-- usage-rules-end -->