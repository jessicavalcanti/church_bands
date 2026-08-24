// Guarda entre carregamentos se a barra lateral está recolhida.
//
// Recolher a barra é 100% client-side: o `sidebar_trigger` do SaladUI dispara
// `JS.toggle_attribute`, que só vira atributos no DOM — o servidor nunca fica
// sabendo por ali. Este hook observa esses atributos e **grava a escolha num
// cookie**, que é como o shadcn/ui — de quem o SaladUI é porte — resolve o
// mesmo problema.
//
// O cookie é o que permite ao servidor renderizar a barra já recolhida
// (`Layouts.app/1` lê `sidebar_state` da sessão e passa `state=` ao
// `<.sidebar>`). Antes disto a escolha vivia no `localStorage`, que o servidor
// não enxerga: a barra chegava sempre expandida e um `<script>` inline, logo
// abaixo dela, corrigia os atributos antes da primeira pintura. Funcionava, e
// custava um `nonce` da CSP viajando pela sessão a cada resposta.
//
// O hook não mora na própria barra: `<.sidebar>` monta os atributos dela e não
// repassa os nossos. Ele fica num ponto de apoio invisível que aponta para a
// barra por `data-sidebar-target`.
//
// Sobram dois momentos em que o HTML que chega pode contradizer a tela, e cada
// um tem a sua defesa:
//
//   * navegação ao vivo para outra LiveView (`navigate`) — a tela nova é
//     montada e o hook remontado no mesmo passo, sem pintura no meio;
//     `restore/0` corrige a barra ali, antes de o quadro fechar;
//   * re-render da mesma LiveView — o elemento é reaproveitado e o morphdom
//     reescreveria os atributos com o que o servidor mandou no mount, que pode
//     ser anterior ao último clique no gatilho. É o que
//     `preserveSidebarState/2` impede, em `dom.onBeforeElUpdated`.
// O mesmo nome de cookie do shadcn/ui, lido no servidor por
// `ChurchBandsWeb.SidebarState`.
const KEY = "sidebar_state"

// Sete dias, como o `SIDEBAR_COOKIE_MAX_AGE` do shadcn: tempo de a escolha
// sobreviver às idas e vindas de uma semana sem virar preferência eterna.
const MAX_AGE = 60 * 60 * 24 * 7

// A classe que o próprio SaladUI põe na raiz da barra do desktop — a mesma que
// o `sidebar_rail` usa para achar quem alternar.
const ROOT_CLASS = "sidebar-root"

const read = () => {
  const match = document.cookie.match(new RegExp(`(?:^|; )${KEY}=([^;]*)`))
  return match ? decodeURIComponent(match[1]) : null
}

// `SameSite=Lax` porque o cookie só precisa valer na navegação do próprio
// site, e sem `Secure` porque o desenvolvimento roda em `http://localhost` —
// não há segredo aqui, é a largura de uma barra.
const write = (state) => {
  document.cookie = `${KEY}=${state}; path=/; max-age=${MAX_AGE}; samesite=lax`
}

// Mantém no HTML que chega do servidor o estado que está valendo na tela. Sem
// isto, um re-render qualquer devolveria a barra para "expandido" no meio da
// navegação — e, como o elemento é reaproveitado, a largura ainda animaria os
// 200ms da transição, que é o piscada que se vê.
export const preserveSidebarState = (from, to) => {
  if (!from.classList || !from.classList.contains(ROOT_CLASS)) return

  for (const name of ["data-state", "data-collapsible"]) {
    const value = from.getAttribute(name)
    if (value !== null) to.setAttribute(name, value)
  }
}

export const SidebarState = {
  mounted() {
    this.sidebar = this.findSidebar()
    if (!this.sidebar) return

    this.restore()
    this.observer = new MutationObserver(() => write(this.sidebar.dataset.state || "expanded"))
    this.observer.observe(this.sidebar, {attributes: true, attributeFilter: ["data-state"]})
  },

  destroyed() {
    this.observer && this.observer.disconnect()
  },

  // Procurar a partir da raiz da própria árvore, e não do `document`: numa
  // navegação abortada no meio do caminho a tela nova fica solta, fora do
  // documento, e ali `document.getElementById` acharia a barra da tela
  // **antiga**. A correção iria para o elemento errado.
  findSidebar() {
    const id = this.el.dataset.sidebarTarget
    if (!id) return null

    const root = this.el.getRootNode()
    return root.querySelector(`#${CSS.escape(id)}`)
  },

  // Os dois atributos andam juntos: é o par que o `toggle_sidebar/1` do
  // SaladUI alterna, e é de `data-collapsible` que saem as classes do modo só
  // com ícones.
  restore() {
    if (read() !== "collapsed") return

    this.sidebar.setAttribute("data-state", "collapsed")
    this.sidebar.setAttribute("data-collapsible", this.el.dataset.sidebarCollapsible || "icon")
  }
}
