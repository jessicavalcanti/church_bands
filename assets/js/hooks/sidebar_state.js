// Guarda entre carregamentos se a barra lateral está recolhida.
//
// Recolher a barra é 100% client-side: o `sidebar_trigger` do SaladUI dispara
// `JS.toggle_attribute`, que só vira atributos no DOM — o servidor nunca fica
// sabendo. Este hook observa esses atributos, grava a escolha no
// `localStorage` e a aplica de volta a cada montagem, no mesmo espírito do
// script de tema do `root.html.heex`.
//
// O hook não mora na própria barra: `<.sidebar>` monta os atributos dela e não
// repassa os nossos. Ele fica num ponto de apoio invisível que aponta para a
// barra por `data-sidebar-target`.
//
// Como o servidor sempre renderiza a barra expandida (o `state` do
// `<.sidebar>` é do componente, não do usuário), todo HTML que chega
// contradiz a escolha de quem está usando. São três momentos, e cada um tem a
// sua defesa:
//
//   * carregamento de página inteira — a barra é pintada antes de este
//     arquivo sequer existir. Quem defende não é o hook: é o script inline do
//     `Layouts.app/1`, logo abaixo da barra, que roda antes da primeira
//     pintura. Sem ele a barra abre expandida e fecha animando, que é a
//     piscada da tela;
//   * navegação ao vivo para outra LiveView (`navigate`) — a tela nova é
//     montada e o hook remontado no mesmo passo, sem pintura no meio;
//     `restore/0` corrige a barra ali, antes de o quadro fechar;
//   * re-render da mesma LiveView — o elemento é reaproveitado e o morphdom
//     reescreveria os atributos com o "expandido" do servidor. É o que
//     `preserveSidebarState/2` impede, em `dom.onBeforeElUpdated`.
const KEY = "phx:sidebar"

// A classe que o próprio SaladUI põe na raiz da barra do desktop — a mesma que
// o `sidebar_rail` usa para achar quem alternar.
const ROOT_CLASS = "sidebar-root"

const read = () => {
  try {
    return localStorage.getItem(KEY)
  } catch (_error) {
    // Navegador com armazenamento bloqueado: a barra abre expandida e segue.
    return null
  }
}

const write = (state) => {
  try {
    localStorage.setItem(KEY, state)
  } catch (_error) {
    // Sem onde guardar, a escolha vale só para esta visita.
  }
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
