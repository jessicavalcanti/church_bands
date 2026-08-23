defmodule ChurchBandsWeb.ContentSecurityPolicy do
  @moduledoc """
  Escreve o cabeçalho `content-security-policy` de cada resposta HTML.

  `put_secure_browser_headers` já traz `x-frame-options`,
  `x-content-type-options` e companhia, mas não a CSP — e é ela que decide o
  que um XSS eventual consegue fazer depois de acontecer. A aplicação serve
  tudo de casa (a única exceção é a fonte Geist, do Google Fonts), então a
  política é curta: só o próprio domínio.

  ## Os dois scripts inline

  A página tem dois `<script>` escritos no HTML — o do tema, no
  `root.html.heex`, e o da barra lateral, em `ChurchBandsWeb.Layouts.app/1`.
  Os dois existem para corrigir a tela **antes da primeira pintura**, que é o
  que um arquivo externo não garante, e nenhum dos dois passaria por
  `script-src 'self'`.

  Cada resposta ganha então um `nonce` sorteado, que vai no cabeçalho e nos dois
  scripts. Ele chega até eles por dois caminhos, porque as duas molduras são
  renderizadas em lugares diferentes:

    * `conn.assigns.csp_nonce` — o `root.html.heex` é renderizado com a `conn`
    * a sessão — `ChurchBandsWeb.AuthHooks` a lê no `mount` e põe o nonce no
      socket, de onde `Layouts.app/1` o recebe por atributo

  Há ainda um terceiro trecho de código no HTML que não é `<script>`: o `onload`
  do avatar do SaladUI. Atributo de evento não aceita nonce, e a saída para ele
  é o hash — ver `@avatar_onload` abaixo.

  O preço de gravar o nonce na sessão é o cookie ser reescrito a cada resposta.
  A alternativa seria repetir um `session:` em cada `live_session` do router, e
  aí uma `live_session` nova nasceria sem nonce — a barra lateral voltaria a
  piscar, sem nada avisando. Este caminho vale para toda LiveView que passe
  pelos hooks, que são todas.
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
    |> put_session(:csp_nonce, nonce)
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
