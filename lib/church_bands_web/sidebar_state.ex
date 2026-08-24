defmodule ChurchBandsWeb.SidebarState do
  @moduledoc """
  Lê o cookie `sidebar_state` e o entrega a quem desenha a barra lateral.

  Recolher a barra acontece só no navegador — o gatilho do SaladUI vira
  atributos no DOM —, e é o hook `SidebarState` (`assets/js/hooks/`) que grava
  a escolha no cookie, como faz o shadcn/ui. O que este plug faz é o outro
  lado: trazer a escolha de volta para o servidor, para que o HTML **já saia**
  com a barra recolhida.

  É o que resolve a piscada do #31 sem script inline. Antes, a barra chegava
  sempre expandida e um `<script>` logo abaixo dela corrigia os atributos antes
  da primeira pintura; ele custava um `nonce` da CSP gravado na sessão a cada
  resposta, só para poder existir.

  ## Por que a sessão, e não só o assign

  O valor precisa chegar a dois lugares. Para o controller da home basta
  `conn.assigns`; a LiveView, porém, não enxerga cookie no `mount` — o que ela
  recebe é a sessão. Gravar ali faz o valor alcançar toda LiveView que passe
  pelos hooks, que são todas, sem repetir um `session:` em cada `live_session`
  do router.

  **A sessão só é reescrita quando a escolha muda**, e essa comparação é o
  ponto do plug: `put_session/3` marca a sessão como suja, e o cookie de sessão
  volta em toda resposta que a tocar. Escrever a cada requisição é justamente o
  preço que o `nonce` cobrava e que este card veio tirar.
  """
  @behaviour Plug

  import Plug.Conn

  @cookie "sidebar_state"
  @collapsed "collapsed"
  @expanded "expanded"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    state = state_from_cookie(conn)

    conn
    |> assign(:sidebar_state, state)
    |> store(state)
  end

  # Só o valor conhecido vira estado; cookie com qualquer outra coisa escrita
  # dentro é a barra expandida, que é o padrão do componente.
  defp state_from_cookie(conn) do
    case fetch_cookies(conn).cookies[@cookie] do
      @collapsed -> @collapsed
      _other -> @expanded
    end
  end

  defp store(conn, state) do
    if get_session(conn, :sidebar_state) == state do
      conn
    else
      put_session(conn, :sidebar_state, state)
    end
  end
end
