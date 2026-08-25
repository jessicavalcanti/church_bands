defmodule ChurchBandsWeb.Components.UI.ToastTest do
  @moduledoc """
  O toast do SaladUI, que desde a #87 é quem desenha as mensagens de
  `put_flash/3`.

  A moldura monta só o `<.toaster flash={@flash} />` no canto de cima à direita
  (`ChurchBandsWeb.LayoutsTest`), e é esse caminho que as telas exercitam. O
  que fica aqui é o resto do componente: a API de mandar toast direto de um
  `handle_event/3`, que nenhuma tela chama ainda, e as outras posições do
  toaster. Como todo componente copiado para dentro do projeto, ele nasce
  medido — ver `ChurchBandsWeb.Components.UI`.
  """
  use ExUnit.Case, async: true

  import ChurchBandsWeb.Components.UI.Toast
  import Phoenix.LiveViewTest

  describe "toaster/1" do
    test "no canto de baixo à esquerda, ancora pelas bordas de baixo e da esquerda" do
      html = render_component(&toaster/1, %{position: "bottom-left"})

      assert html =~ "bottom-[var(--offset-b)]"
      assert html =~ "left-[var(--offset-l)] items-start"
    end

    test "no centro, não ancora em lado nenhum: centraliza" do
      html = render_component(&toaster/1, %{position: "bottom-center"})

      assert html =~ "left-1/2 -translate-x-1/2 items-center"
    end

    test "a distância da borda pode ser diferente em cada lado" do
      html = render_component(&toaster/1, %{offset: %{top: 8, right: 24}})

      assert html =~ "--offset-t: 8px"
      assert html =~ "--offset-r: 24px"
      # Lado que o mapa não cita fica colado na borda.
      assert html =~ "--offset-b: 0px"
    end

    test "a distância pode vir em qualquer unidade do CSS, não só em pixels" do
      html = render_component(&toaster/1, %{offset: "2rem"})

      assert html =~ "--offset-t: 2rem"
    end

    test "o modelo de conteúdo rico fica na página, para o JavaScript clonar" do
      html =
        render_component(&toaster/1, %{
          template: [%{__slot__: :template, name: "novo-evento", inner_block: bloco("Ensaio")}]
        })

      assert html =~ ~s(data-part="toast-template")
      assert html =~ ~s(data-name="novo-evento")
      assert html =~ "Ensaio"
    end
  end

  describe "toast_flash/1" do
    test "a mensagem já pronta em HTML atravessa como texto" do
      html =
        render_component(&toast_flash/1, %{flash: %{"info" => {:safe, ["Banda ", "salva."]}}})

      assert entradas(html) =~ "Banda salva."
    end

    test "a mensagem montada em pedaços atravessa inteira" do
      html = render_component(&toast_flash/1, %{flash: %{"info" => ["Banda ", "salva."]}})

      assert entradas(html) =~ "Banda salva."
    end

    test "flash vazio não vira toast nenhum" do
      html = render_component(&toast_flash/1, %{flash: %{"info" => "", "error" => nil}})

      assert entradas(html) == "[]"
    end
  end

  describe "mandar toast do servidor" do
    test "toast/3 manda criar um cartão com o texto como título" do
      [comando] = comandos(toast(socket(), "Instrumento salvo."))

      assert comando.target == "toaster"
      assert comando.command == "add"
      assert comando.params.title == "Instrumento salvo."
      assert comando.params.variant == "default"
      # O id é de quem cria, para poder atualizar ou dispensar o cartão depois.
      assert comando.params.id =~ ~r/^toast-\d+$/
    end

    test "sem texto, os opts vão inteiros — é assim que se chama um modelo" do
      [comando] = comandos(toast(socket(), template: "novo-evento"))

      assert comando.params.template == "novo-evento"
      refute Map.has_key?(comando.params, :title)
    end

    test "toast/4 fala com um toaster que não é o padrão" do
      [comando] = comandos(toast(socket(), "outro-toaster", "Salvo.", []))

      assert comando.target == "outro-toaster"
    end

    test "a variante pode vir como átomo, e chega como texto para o JavaScript" do
      [comando] = comandos(toast(socket(), "Salvo.", variant: :success))

      assert comando.params.variant == "success"
    end

    test "duração infinita vira a palavra que o JavaScript entende" do
      [comando] = comandos(toast(socket(), "Salvo.", duration: :infinity))

      assert comando.params.duration == "infinity"
    end

    test "duração em milissegundos viaja como número" do
      [comando] = comandos(toast(socket(), "Salvo.", duration: 8000))

      assert comando.params.duration == 8000
    end

    test "sem duração, a chave nem viaja: quem decide é o componente" do
      [comando] = comandos(toast(socket(), "Salvo."))

      refute Map.has_key?(comando.params, :duration)
    end

    test "cada atalho de variante manda a sua" do
      for {atalho, variante} <- [
            {&toast_success/2, "success"},
            {&toast_error/2, "error"},
            {&toast_warning/2, "warning"},
            {&toast_info/2, "info"}
          ] do
        [comando] = comandos(atalho.(socket(), "Salvo."))

        assert comando.params.variant == variante
      end
    end

    test "toast_update/3 corrige um cartão que já está na tela, pelo id" do
      [comando] = comandos(toast_update(socket(), "toast-1", title: "Salvo!", variant: "success"))

      assert comando.command == "update"
      assert comando.params.id == "toast-1"
      assert comando.params.title == "Salvo!"
      assert comando.params.variant == "success"
    end

    test "toast_dismiss/3 tira um cartão pelo id" do
      [comando] = comandos(toast_dismiss(socket(), "toaster", "toast-1"))

      assert comando.command == "dismiss"
      assert comando.params == %{id: "toast-1"}
    end

    test "sem id, toast_dismiss/1 limpa a pilha inteira" do
      [comando] = comandos(toast_dismiss(socket()))

      assert comando.command == "dismiss"
      assert comando.params == %{}
    end
  end

  describe "put_toast/4" do
    test "no socket, é toast com a variante do tipo da mensagem" do
      [comando] = comandos(put_toast(socket(), :error, "Não foi possível salvar."))

      assert comando.params.variant == "error"
      assert comando.params.title == "Não foi possível salvar."
    end

    test "no conn continua flash: a página que vai mostrá-lo ainda nem existe" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Phoenix.Controller.fetch_flash([])
        |> put_toast(:info, "Sessão encerrada.")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Sessão encerrada."
    end
  end

  defp socket, do: %Phoenix.LiveView.Socket{}

  defp comandos(socket) do
    for ["saladui:command", payload] <- socket.private.live_temp[:push_events], do: payload
  end

  defp entradas(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-component=\"toast-flash\"]")
    |> LazyHTML.attribute("data-entries")
    |> List.first()
  end

  defp bloco(texto), do: fn _, _ -> texto end
end
