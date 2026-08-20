# Church Bands

Sistema de gerenciamento do grupo de louvor — Elixir + Phoenix LiveView + PostgreSQL.

Código, rotas, contextos, tabelas e colunas em inglês; textos de tela em português.

## Rodando com Docker

Sobe app + banco sem precisar de Elixir/Erlang/Postgres na máquina:

```sh
docker compose up
```

A aplicação fica em <http://localhost:4000>.

## Rodando na máquina

Requer Elixir/Erlang e um PostgreSQL acessível em `localhost` (ajustável por
`DATABASE_HOST`, `DATABASE_USER` e `DATABASE_PASSWORD`).

```sh
mix setup       # deps, cria o banco, roda migrations e seeds, prepara assets
mix phx.server
```

## Testes

```sh
mix test        # cria/migra o banco de teste automaticamente
mix precommit   # compila sem warnings, formata e roda os testes
```

Para a validação manual — o que percorrer na aplicação rodando antes de
entregar uma fase — siga o [roteiro de testes](roteiro-de-testes.md).

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
por Pull Request, force-push e deleção estão bloqueados, e as conversas de
revisão precisam estar resolvidas antes do merge.

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

1. `mix run priv/repo/seeds.exs` cria um usuário de cada papel;
2. acesse <http://localhost:4000/login> e entre com um dos e-mails abaixo,
   todos com a senha `senha123456`:

| E-mail | Perfil |
|---|---|
| `pastora@churchbands.local` | Pastor |
| `louvor@churchbands.local` | Líder de Louvor |
| `musica@churchbands.local` | Músico |

Para percorrer o fluxo de convite ponta a ponta, envie um convite em
`/admin/invites` e abra o link de ativação a partir do e-mail. Os e-mails
enviados em desenvolvimento não saem da máquina — leia-os em
<http://localhost:4000/dev/mailbox>.

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
