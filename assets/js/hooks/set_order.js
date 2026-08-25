// Reordenar o set arrastando as linhas (US 3.6).
//
// A sequência do culto é a informação principal da tela do set: a ordem em que
// a banda toca é o que a folha impressa mostraria. Arrastar é o gesto que diz
// isso — subir e descer por botão faria mover a última música para o topo
// custar quatro cliques.
//
// **Sobre a API nativa de arraste do HTML**, sem biblioteca: o projeto não tem
// uma de drag and drop e não vai ter. `draggable` + `dragstart`/`dragover`/
// `drop` são quatro eventos, e o que sobra deles é o reordenamento no DOM e um
// `pushEvent` no solte.
//
// **A ordem que sai daqui não é confiável, e o servidor sabe disso**: o hook
// manda a lista de ids, e `Schedule.reorder_set/2` recusa o conjunto que não
// for exatamente o do set. Quem tem o console aberto manda o que quiser.
//
// Os `dragover` são contínuos enquanto o dedo se move, e é neles que a linha
// arrastada troca de lugar — o resultado é que o set se reorganiza embaixo do
// cursor, e não só quando se solta. O `pushEvent` fica no `drop`: uma
// gravação por gesto, e não uma por pixel.
const ITEM = "[data-set-item]"

export const SetOrder = {
  mounted() {
    this.dragged = null
    this.el.addEventListener("dragstart", (event) => this.start(event))
    this.el.addEventListener("dragover", (event) => this.over(event))
    this.el.addEventListener("dragend", () => this.end())
    this.el.addEventListener("drop", (event) => this.drop(event))
  },

  start(event) {
    this.dragged = event.target.closest(ITEM)
    if (!this.dragged) return

    this.dragged.setAttribute("data-dragging", "")
    // `move` é o que troca o cursor do navegador para a seta de mover; sem
    // isto o gesto se anuncia como cópia, que não é o que está acontecendo.
    event.dataTransfer.effectAllowed = "move"
    // O Firefox não inicia o arraste sem carga no `dataTransfer`, mesmo que
    // ninguém vá lê-la — o id serve de carga e de rastro no depurador.
    event.dataTransfer.setData("text/plain", this.dragged.dataset.setItem)
  },

  over(event) {
    if (!this.dragged) return

    // Sem o `preventDefault` o navegador entende que aqui não se pode soltar,
    // e o `drop` nunca chega.
    event.preventDefault()

    const target = event.target.closest(ITEM)
    if (!target || target === this.dragged) return

    // Qual das metades da linha o cursor está determina se a arrastada entra
    // antes ou depois — sem isso, passar por cima de uma linha alta faria as
    // duas trocarem de lugar sem parar.
    const box = target.getBoundingClientRect()
    const after = event.clientY > box.top + box.height / 2

    target.parentNode.insertBefore(this.dragged, after ? target.nextSibling : target)
  },

  drop(event) {
    if (!this.dragged) return

    event.preventDefault()
    this.pushEvent("reorder", {ids: this.ids()})
  },

  end() {
    this.dragged && this.dragged.removeAttribute("data-dragging")
    this.dragged = null
  },

  ids() {
    return Array.from(this.el.querySelectorAll(ITEM), (item) => item.dataset.setItem)
  }
}
