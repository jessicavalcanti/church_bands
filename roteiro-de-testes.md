# Roteiro de testes

Roteiro de **validação manual** do Church Bands: o que percorrer na aplicação
rodando para confirmar que cada funcionalidade entregue continua funcionando.

Ele existe porque a suíte automatizada prova que o código faz o que foi
combinado, mas não que a experiência inteira está de pé — o e-mail que chega, o
link que abre, o botão que aparece para uma pessoa e some para outra. É esse o
papel deste documento.

**Quando usar**

- **Antes de cada merge `develop` → `main`** (o "release" de cada fase), rodando
  o roteiro inteiro da fase que está sendo entregue.
- **Ao revisar um Pull Request**, rodando a seção da user story em questão.
- Ao voltar ao projeto depois de um tempo, para reconhecer o que já existe.

**Quando atualizar:** toda vez que uma funcionalidade nova é entregue. A regra
está registrada no `AGENTS.md` — uma user story só está concluída quando o
roteiro cobre o que ela entregou.

---

## Preparação do ambiente

```sh
docker compose up
```

A aplicação sobe em <http://localhost:4000> e as migrations e seeds rodam
sozinhas na primeira subida.

Para começar de um banco limpo — recomendado antes de rodar o roteiro inteiro,
porque os seeds criam a banda de exemplo com elenco:

```sh
docker compose stop app
docker compose run --rm app mix ecto.reset
docker compose up
```

A aplicação precisa estar parada: `mix ecto.drop` não derruba um banco com
conexões abertas, e a aplicação mantém as dela enquanto estiver de pé.

### Usuários criados pelos seeds

Todos entram com a senha `senha123456`.

| E-mail | Nome | Perfil |
|---|---|---|
| `pastora@churchbands.local` | Ana Pastora | Pastor (acesso total) |
| `louvor@churchbands.local` | Bruno Líder de Louvor | Líder de Louvor (acesso total) |
| `musica@churchbands.local` | Carla Musicista | Músico — e Líder da "Banda Jovem" |

A "Banda Jovem" já vem cadastrada, liderada pela Carla, com ela no violão e o
Bruno no vocal (naipe Tenor).

### Onde ler os e-mails

Em desenvolvimento nenhum e-mail sai da máquina: todos ficam em
<http://localhost:4000/dev/mailbox>.

### Se as telas carregarem mas nada responder

É o bundle de JavaScript faltando. O diagnóstico e a correção estão no
[README](README.md#se-as-telas-carregarem-mas-nada-funcionar).

---

## Como ler cada cenário

Cada cenário tem **pré-condição**, **passos** e **resultado esperado**. As
recusas de permissão são cenários de primeira classe, não observações: a regra
central do sistema é *leitura ampla, escrita restrita*, e esconder o botão na
tela nunca foi a autorização — vale sempre tentar a URL na mão.

---

## Fase 1 — Fundação: Acesso e Estrutura

### US 1.1 — Convite de novo integrante

- [ ] **Enviar um convite**
  *Pré-condição:* logada como Pastor ou Líder de Louvor.
  *Passos:* menu **Convites** → **Novo convite** → informe um e-mail que ainda
  não existe no sistema → **Enviar convite**.
  *Esperado:* mensagem "Convite enviado para *e-mail*."; o convite aparece na
  lista com status **Pendente** e data de expiração de 7 dias à frente; o
  e-mail com o link de ativação está em `/dev/mailbox`.

- [ ] **Recusar e-mail que já tem conta**
  *Passos:* envie um convite para `musica@churchbands.local`.
  *Esperado:* o formulário recusa com "já possui uma conta no sistema"; nada é
  enviado.

- [ ] **Recusar convite repetido**
  *Passos:* envie um segundo convite para um e-mail que já está **Pendente**.
  *Esperado:* recusa com "já possui um convite pendente".

- [ ] **Reenviar um convite**
  *Passos:* na lista, **Reenviar** num convite pendente.
  *Esperado:* mensagem "Convite reenviado para *e-mail*."; um novo e-mail em
  `/dev/mailbox`, com link diferente do anterior; o prazo de validade recomeça.
  O link antigo, aberto depois disso, cai na tela de link inválido.

- [ ] **Cancelar um convite**
  *Passos:* **Cancelar** num convite pendente → confirme.
  *Esperado:* mensagem de cancelamento; status muda para **Cancelado** e o
  botão de cancelar some. O link enviado deixa de funcionar.

- [ ] **Músico comum não chega aos convites**
  *Pré-condição:* logada como `musica@churchbands.local`.
  *Passos:* confira o menu e depois acesse `/admin/invites` digitando a URL.
  *Esperado:* o item **Convites** não aparece no menu; a URL redireciona para a
  home com "Você não tem permissão para acessar esta página."

- [ ] **Visitante não chega aos convites**
  *Passos:* deslogada, acesse `/admin/invites`.
  *Esperado:* vai para o login com "Você precisa entrar para acessar esta
  página."

### US 1.2 — Ativação de conta e Login

- [ ] **Ativar a conta pelo link do convite**
  *Pré-condição:* um convite pendente e o e-mail aberto em `/dev/mailbox`.
  *Passos:* abra o link de ativação → preencha nome, senha (ao menos 8
  caracteres, com letras e números) e confirmação → **Ativar conta**.
  *Esperado:* o e-mail aparece fixo na tela e não é editável; ao salvar, a
  mensagem "Conta ativada, *nome*! Faça login para entrar." e a ida para o
  login já com o e-mail preenchido. Na lista de convites, o status virou
  **Aceito**.

- [ ] **Senha fraca e confirmação divergente**
  *Passos:* tente ativar com senha curta, sem número, e depois com a
  confirmação diferente da senha.
  *Esperado:* o formulário recusa cada caso e a conta não é criada.
  > As mensagens de senha curta e nome curto ainda aparecem em inglês — é o
  > débito **DT-1** da issue #11, não um defeito novo.

- [ ] **Entrar no sistema**
  *Passos:* na tela de login, e-mail e senha da conta recém-ativada.
  *Esperado:* "Bem-vindo(a), *nome*!"; o menu passa a mostrar **Bandas** e o
  nome com o perfil.

- [ ] **Credenciais incorretas**
  *Passos:* tente entrar com a senha errada, e depois com um e-mail que não
  existe.
  *Esperado:* nos dois casos, "E-mail ou senha incorretos." — a mensagem não
  revela se o e-mail existe.

- [ ] **Link de ativação usado mais de uma vez**
  *Passos:* abra de novo o link de um convite já aceito.
  *Esperado:* tela "Link inválido", com o caminho para o login.

- [ ] **Sair do sistema**
  *Passos:* **Sair** no menu.
  *Esperado:* "Você saiu do sistema." e volta ao login; acessar `/bands` na URL
  pede login de novo.

### US 1.3 — Cadastro de Banda

- [ ] **Cadastrar uma banda**
  *Pré-condição:* logada como Pastor ou Líder de Louvor.
  *Passos:* **Bandas** → **Nova banda** → nome, Líder de Banda e descrição →
  **Cadastrar banda**.
  *Esperado:* "Banda *nome* cadastrada."; a banda aparece na lista com o líder.
  O select de líder só oferece contas já ativas.

- [ ] **Validações do formulário**
  *Passos:* tente salvar sem nome e sem líder.
  *Esperado:* "informe o nome da banda" e "escolha o Líder de Banda".

- [ ] **Editar a banda**
  *Passos:* **Editar** numa banda → mude nome, descrição e líder → salve.
  *Esperado:* "Banda *nome* atualizada."; a lista reflete o novo líder.

- [ ] **O Líder de Banda edita a própria banda, e só ela**
  *Pré-condição:* logada como `musica@churchbands.local`, líder da Banda Jovem.
  *Passos:* na lista, confira os botões da Banda Jovem e os de outra banda;
  depois acesse na URL o `/bands/:id/edit` de uma banda que ela não lidera.
  *Esperado:* **Editar** aparece só na Banda Jovem; **Nova banda** e **Excluir**
  não aparecem em lugar nenhum; a URL da outra banda redireciona para `/bands`
  com "Você não tem permissão para editar esta banda."

- [ ] **Excluir é só do acesso total**
  *Passos:* como Pastor, **Excluir** numa banda → confirme.
  *Esperado:* "Banda *nome* excluída."; a banda some da lista.

- [ ] **Músico comum vê a lista, sem botões**
  *Pré-condição:* logada como um músico que não lidera banda nenhuma.
  *Passos:* acesse `/bands` e depois `/bands/new` na URL.
  *Esperado:* a lista aparece inteira, sem botão de ação; `/bands/new`
  redireciona para a home com "Você não tem permissão para acessar esta
  página."

### US 1.4 — Cadastro de músico e vínculo a banda(s)

- [ ] **Adicionar um instrumentista**
  *Pré-condição:* logada como Líder da banda, Pastor ou Líder de Louvor.
  *Passos:* **Bandas** → **Integrantes** na banda → digite parte do nome ou do
  e-mail de um músico ativo → clique na sugestão → função **Instrumentista** →
  instrumento (o campo sugere os mais comuns, mas aceita qualquer texto) →
  **Adicionar à banda**.
  *Esperado:* "*nome* entrou na *banda*."; a pessoa aparece no **Elenco atual**
  com o instrumento, e o formulário volta em branco para adicionar a próxima.

- [ ] **Adicionar um vocalista**
  *Passos:* mesmo fluxo, com função **Vocalista** e um naipe (Soprano,
  Contralto, Tenor ou Baixo).
  *Esperado:* entra no elenco como "Vocal — *naipe*".

- [ ] **O campo depende da função**
  *Passos:* alterne a função entre Instrumentista e Vocalista.
  *Esperado:* **Instrumento** aparece só para instrumentista e **Naipe** só
  para vocalista; ao trocar, o campo do outro tipo some e o valor que estava
  nele não é gravado.

- [ ] **Validações do formulário**
  *Passos:* tente adicionar sem escolher músico; depois com músico escolhido e
  função Instrumentista sem instrumento; depois Vocalista sem naipe.
  *Esperado:* "escolha o músico", "informe o instrumento" e "escolha o naipe",
  cada uma junto do campo correspondente. Nada é gravado.

- [ ] **A busca só oferece quem pode entrar**
  *Passos:* busque por alguém que já é integrante da banda; depois por alguém
  que foi convidado mas ainda não ativou a conta.
  *Esperado:* nenhum dos dois aparece; a tela explica que só constam contas
  ativas que ainda não estão nesta banda.

- [ ] **Trocar o músico escolhido**
  *Passos:* escolha alguém e clique em **Trocar**.
  *Esperado:* a escolha é desfeita e o campo de busca volta, vazio.

- [ ] **O mesmo músico em duas bandas, com função própria em cada uma**
  *Passos:* adicione um músico que já está em outra banda, aqui com função
  diferente.
  *Esperado:* o vínculo é criado; nas duas bandas ele consta, cada uma com a
  sua função — a da outra banda não muda.

- [ ] **Remover um integrante**
  *Passos:* **Remover** numa linha do elenco → confirme.
  *Esperado:* "*nome* saiu da *banda*."; sai do elenco, **continua existindo no
  sistema** (entra no login normalmente) e volta a aparecer na busca desta
  banda.

- [ ] **O Líder de Banda cuida só do elenco da própria banda**
  *Pré-condição:* logada como o líder de uma banda.
  *Passos:* confira o botão **Integrantes** nas outras bandas da lista e depois
  acesse na URL o `/bands/:id/members/new` de uma delas.
  *Esperado:* o botão só aparece na própria banda; a URL da outra redireciona
  para `/bands` com "Você não tem permissão para gerenciar os integrantes desta
  banda."

- [ ] **Músico comum não gerencia elenco nenhum**
  *Passos:* logada como músico sem liderança, acesse
  `/bands/:id/members/new` na URL.
  *Esperado:* recusa com a mesma mensagem, de volta em `/bands`.

- [ ] **Banda inexistente**
  *Passos:* acesse `/bands/999999/members/new`.
  *Esperado:* volta para `/bands` com "Banda não encontrada."

---

## Fase 2 — Repertório Musical

Nada entregue ainda.

## Fase 3 — Calendário e Escala

Nada entregue ainda.

## Fase 4 — Equipe Técnica

Nada entregue ainda.

---

## Testes automatizados

O roteiro acima é a validação manual; a rede de proteção do dia a dia é a
suíte:

```sh
mix precommit   # compila sem warnings, formata e roda os testes
mix test        # só os testes
```

| Assunto | Onde |
|---|---|
| Contas, convites, ativação e login | `test/church_bands/accounts_test.exs` |
| Bandas, autorização e vínculos de integrantes | `test/church_bands/bands_test.exs` |
| Convites (tela) | `test/church_bands_web/live/invite_live/index_test.exs` |
| Ativação de conta (tela) | `test/church_bands_web/live/invite_live/activate_test.exs` |
| Login e logout | `test/church_bands_web/live/session_live_test.exs`, `test/church_bands_web/controllers/session_controller_test.exs` |
| Bandas (telas) | `test/church_bands_web/live/band_live/` |
| Integrantes da banda (tela) | `test/church_bands_web/live/member_live/form_test.exs` |

Um cenário deste roteiro que dê para cobrir por teste automatizado **deve** ser
coberto — o roteiro manual é para o que a suíte não alcança: o e-mail que
chega, o link que abre, o botão que aparece na tela certa.
