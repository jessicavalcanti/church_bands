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

## Perfis de acesso

| Perfil | `global_role` | Acesso |
|---|---|---|
| Pastor | `pastor` | total |
| Líder de Louvor | `worship_leader` | total |
| Líder de Banda | — | derivado de `bands.leader_id` |
| Músico / Técnico | `member` | leitura ampla, escrita no próprio perfil |

Regra central: **leitura ampla, escrita restrita**.
