# Church Bands

Sistema de gerenciamento do grupo de louvor — Elixir + Phoenix LiveView + PostgreSQL.

Código, rotas, contextos, tabelas e colunas em inglês; textos de tela em português.

## Requisitos

| O quê | Versão | Onde está fixada |
|---|---|---|
| Elixir | 1.20.3 | `Dockerfile.dev` e `.github/workflows/ci.yml` |
| Erlang/OTP | 29.0.5 | idem |
| PostgreSQL | 16 | `docker-compose.yml` e o serviço do CI |

São as mesmas versões na máquina de quem desenvolve, no container e no CI —
é isso que faz o veredito local valer o mesmo que o da esteira. O Elixir 1.20 é
piso, não preferência: o `config/runtime.exs` do Phoenix 1.8 usa o modificador
de regex `~r"..."E`, que não existe antes dele.

Rodando por Docker, nada disso precisa estar instalado.

## Rodando com Docker

Sobe app + banco sem precisar de Elixir/Erlang/Postgres na máquina:

```sh
docker compose up
```

A aplicação fica em <http://localhost:4000>. O compose roda `mix ecto.setup` a
cada subida, então banco, migrations e seeds já vêm prontos.

## Rodando na máquina

Requer as versões da tabela acima e um PostgreSQL acessível em `localhost`
(ajustável por `DATABASE_HOST`, `DATABASE_USER` e `DATABASE_PASSWORD`).

```sh
mix setup       # deps, cria o banco, roda migrations e seeds, prepara assets
mix phx.server
```

## Estrutura do código

```
lib/church_bands/            o domínio: dois contextos e seus schemas
  accounts.ex                usuários, convites, autenticação e senha
  bands.ex                   bandas e vínculos de músicos
lib/church_bands_web/
  router.ex                  as rotas, agrupadas por permissão em live_sessions
  auth_hooks.ex              os hooks on_mount que autorizam cada live_session
  user_auth.ex               os plugs de sessão das requisições HTTP
  live/                      uma pasta por assunto, uma LiveView por tela
  components/layouts.ex      as duas molduras: o portal e as telas públicas
  components/core_components.ex   os componentes do projeto
  components/ui/             os componentes do SaladUI, copiados e editáveis
priv/repo/                   migrations e seeds
test/                        espelha lib/, com fixtures em test/support
```

Duas regras dão a forma do resto:

- **os contextos decidem, as LiveViews perguntam** — `full_access?/1`,
  `band_leader?/2` e `manage_members?/2` são a fonte única das permissões, e
  nenhuma tela reimplementa a regra;
- **leitura ampla, escrita restrita** — toda tela de escrita passa por um hook
  de `live_session` **e** reconsulta o contexto antes de agir. Esconder o botão
  não é autorização.

As convenções do projeto — board, débitos técnicos, design system, gitflow,
padrões de Elixir e de LiveView — estão no `AGENTS.md`, na raiz.

## Testes e qualidade

```sh
mix test        # cria/migra o banco de teste automaticamente
mix precommit   # o portão único de qualidade — rode antes de abrir o PR
```

`mix precommit` é a definição única do que precisa passar, e faz mais do que o
nome sugere:

| Passo | O que reprova |
|---|---|
| `compile --warnings-as-errors` | qualquer warning de compilação |
| `deps.unlock --unused` | dependência no `mix.lock` que ninguém usa |
| `format` | código fora do formatador |
| `credo --strict` | consistência e complexidade |
| `sobelow --exit` | falha de segurança específica de Phoenix |
| `deps.audit` | CVE conhecida em alguma dependência |
| `coveralls` | **cobertura abaixo de 100%** |

Duas coisas costumam pegar quem chega: `format` e `deps.unlock --unused`
**corrigem** em vez de reclamar — por isso o CI confere a árvore depois —, e a
cobertura mínima é **100%**, então baixá-la reprova o PR mesmo com todos os
testes passando. Para ver o que falta, `mix coveralls.detail --filter <arquivo>`
mostra o código linha a linha, com as não exercitadas em vermelho.

O `.github/workflows/ci.yml` roda **este mesmo alias** num PostgreSQL de
serviço a cada Pull Request, e depois confere que a árvore ficou limpa
(`git diff --exit-code`) — é o que pega o que `format` e `deps.unlock`
corrigiriam em silêncio. O check é **obrigatório** para o merge nas duas
branches protegidas.

### Validação manual

O que percorrer na aplicação rodando antes de fechar uma fase está no
**roteiro de testes**, um checklist interativo em que cada caso diz quem você
precisa ser, o que fazer e o que tem que acontecer; as marcações ficam
guardadas no navegador.

- publicado em <https://claude.ai/code/artifact/6d6d9ce9-7ad1-45ab-9d73-2560fa8ed7f1> —
  é o link para mandar a quem vai validar sem clonar o repositório;
- ou abra `roteiro-de-testes.html` direto no navegador.

## Fluxo de branches

O projeto segue um gitflow simplificado:

| Branch | Papel |
|---|---|
| `main` | Somente pacotes validados, prontos para produção. Recebe merge apenas da `develop`. |
| `develop` | Branch de integração e **branch padrão** do repositório. É onde a aplicação completa é validada. |
| `feat/us-X.Y-<slug>` | Uma branch por user story, criada a partir da `develop`. |

```
feat/us-1.2-account-activation-login ──PR──▶ develop ──PR──▶ main
```

`main` e `develop` são protegidas: push direto é recusado, toda mudança entra
por Pull Request, force-push e deleção estão bloqueados, o CI precisa passar e
as conversas de revisão precisam estar resolvidas antes do merge.

```sh
git switch develop && git pull
git switch -c feat/us-1.2-account-activation-login
# ... commits ...
git push -u origin feat/us-1.2-account-activation-login
gh pr create --base develop
```

O merge `develop` → `main` é o "release": só acontece quando o pacote inteiro
foi validado.

## Perfis de acesso

| Perfil | `global_role` | Acesso |
|---|---|---|
| Pastor | `pastor` | total |
| Líder de Louvor | `worship_leader` | total |
| Líder de Banda | — | derivado de `bands.leader_id` |
| Músico / Técnico | `member` | leitura ampla, escrita no próprio perfil |

Regra central: **leitura ampla, escrita restrita**.

## Entrando no sistema durante o desenvolvimento

Os seeds (`mix run priv/repo/seeds.exs`, já incluídos no `mix setup` e no
`docker compose up`) montam o cenário inteiro do roteiro de testes: **12
usuários e 2 bandas com elenco completo**, com instrumentos e naipes variados.
Não é preciso cadastrar nada na mão.

A **Banda A** começa com a líder já vinculada e tocando violão; a **Banda B**
começa com o líder **sem vínculo** — é o estado "Líder de Banda ainda sem
função", que a página do elenco cobra com um aviso. Os dois começos possíveis
já vêm representados.

Rodar os seeds de novo não duplica nada, e `mix ecto.reset` volta exatamente ao
estado descrito acima, jogando fora o que a validação manual mexeu.

Acesse <http://localhost:4000/login> e entre com um destes e-mails, todos com a
senha `senha123456`:

| E-mail | Quem é | Perfil |
|---|---|---|
| `pastor@churchbands.local` | André Pastor | Pastor |
| `louvor@churchbands.local` | Bruno Líder de Louvor | Líder de Louvor |
| `musica@churchbands.local` | Carla Musicista | Músico — e Líder da Banda A |

Para percorrer o fluxo de convite ponta a ponta, envie um convite em
`/admin/invites` e abra o link de ativação a partir do e-mail. Os e-mails
enviados em desenvolvimento não saem da máquina — leia-os em
<http://localhost:4000/dev/mailbox>.

## Variáveis de ambiente em produção

A Fase 1 não faz deploy, mas `config/runtime.exs` já espera o seguinte quando
`MIX_ENV=prod`:

| Variável | Obrigatória | Para quê |
|---|---|---|
| `DATABASE_URL` | **sim** — sem ela a aplicação nem sobe | conexão com o Postgres (`ecto://user:pass@host/base`) |
| `SECRET_KEY_BASE` | **sim** — idem | assina o cookie de sessão; gere com `mix phx.gen.secret` |
| `PHX_HOST` | não | o host público que entra nas URLs geradas (padrão `example.com`) |
| `PORT` | não | porta HTTP (padrão `4000`) |
| `POOL_SIZE` | não | conexões no pool do Ecto (padrão `10`) |
| `ECTO_IPV6` | não | `true` ou `1` para conectar ao banco por IPv6 |
| `DNS_CLUSTER_QUERY` | não | a consulta DNS que agrupa os nós, quando houver mais de um |
| `PHX_SERVER` | não | `true` para o release começar a servir HTTP (`PHX_SERVER=true bin/church_bands start`) |

As duas obrigatórias levantam uma exceção com instruções na inicialização —
melhor descobrir assim do que em produção pela metade.

### Se as telas carregarem mas nada funcionar

Sintoma: as páginas aparecem, mas botões e formulários não respondem, e o botão
"Sair" cai num erro de rota inexistente.

Quase sempre é o bundle de JavaScript faltando — `priv/static/assets/` é
ignorado pelo git, e o `esbuild --watch` só constrói na inicialização e a cada
mudança de arquivo, então se o bundle sumir nada o regenera sozinho. Sem ele o
LiveView não conecta e nenhuma interação funciona.

Confirme com `curl -o /dev/null -w '%{http_code}\n' localhost:4000/assets/js/app.js`
(deve ser `200`, não `404`) e resolva com:

    docker compose exec app mix assets.build
