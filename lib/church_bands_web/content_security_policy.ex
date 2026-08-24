defmodule ChurchBandsWeb.ContentSecurityPolicy do
  @moduledoc """
  Escreve o cabeçalho `content-security-policy` de cada resposta HTML.

  `put_secure_browser_headers` já traz `x-frame-options`,
  `x-content-type-options` e companhia, mas não a CSP — e é ela que decide o
  que um XSS eventual consegue fazer depois de acontecer. A aplicação serve
  tudo de casa (a única exceção é a fonte Geist, do Google Fonts), então a
  política é curta: só o próprio domínio.

  ## O script inline

  A página tem **um** `<script>` escrito no HTML: o do tema, no
  `root.html.heex`. Ele existe para pôr a classe `.dark` **antes da primeira
  pintura**, que é o que um arquivo externo não garante, e não passaria por
  `script-src 'self'`.

  Cada resposta ganha então um `nonce` sorteado, que vai no cabeçalho e no
  script. Ele chega até lá por `conn.assigns.csp_nonce` — o `root.html.heex` é
  renderizado com a `conn`.

  **Eram dois scripts.** O segundo ficava em `ChurchBandsWeb.Layouts.app/1` e
  corrigia a barra lateral recolhida antes da pintura; para assiná-lo, o nonce
  precisava atravessar a **sessão** até a LiveView, e o cookie de sessão era
  reescrito a cada resposta por causa disso. A barra passou a guardar o estado
  num cookie próprio, como no shadcn (`ChurchBandsWeb.SidebarState`), e o
  servidor a renderiza recolhida sem script nenhum — o nonce voltou a viver só
  no assign.

  Há ainda um trecho de código no HTML que não é `<script>`: o `onload` do
  avatar do SaladUI. Atributo de evento não aceita nonce, e a saída para ele é
  o hash — ver `@avatar_onload` abaixo.
  """
  @behaviour Plug

  import Plug.Conn

  # O `<.avatar_image>` do SaladUI nasce com `style="display:none"` e se mostra
  # sozinho num `onload` inline, para não piscar a foto meio carregada. Nonce
  # não vale para atributo de evento — só `'unsafe-hashes'` com o hash exato do
  # que está escrito ali. É o handler que a barra lateral usa para a foto de
  # quem está logado; mudou o componente, muda o hash, e o teste da política
  # avisa.
  @avatar_onload "this.style.display=''"
  @avatar_onload_hash Base.encode64(:crypto.hash(:sha256, @avatar_onload))

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce))
  end

  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}' 'unsafe-hashes' 'sha256-#{@avatar_onload_hash}'",
        # `'unsafe-inline'` aqui é sobre o atributo `style=`, que vem de dentro
        # dos componentes do SaladUI (a barra lateral, o menu suspenso) e não
        # tem como levar nonce: nonce vale para a tag `<style>`, nunca para o
        # atributo. Estilo inline não executa código — o que a CSP está
        # segurando de verdade é o `script-src` acima.
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src 'self' https://fonts.gstatic.com",
        # `https:` porque a foto de perfil é uma URL escolhida por cada pessoa,
        # em qualquer host (R-4) — enquanto não houver upload, não há como
        # estreitar isto.
        "img-src 'self' data: https:",
        "connect-src 'self'",
        "form-action 'self'",
        "base-uri 'self'",
        "object-src 'none'",
        "frame-ancestors 'none'"
      ],
      "; "
    )
  end
end
