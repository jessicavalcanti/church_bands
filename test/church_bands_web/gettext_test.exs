defmodule ChurchBandsWeb.GettextTest do
  @moduledoc """
  A rede de proteção do DT-1: toda validação sem `message:` explícito cai na
  mensagem padrão do Ecto, e o gettext precisa devolvê-la em português.

  Sem isso, uma validação nova escrita sem `message:` volta a mostrar inglês na
  tela sem que nenhum teste reclame.
  """
  use ExUnit.Case, async: true

  alias ChurchBandsWeb.CoreComponents

  test "a aplicação fala português" do
    assert Gettext.get_locale(ChurchBandsWeb.Gettext) == "pt_BR"
  end

  test "traduz as mensagens que o Ecto gera sozinho" do
    assert translate({"can't be blank", []}) == "não pode ficar em branco"
    assert translate({"has already been taken", []}) == "já está em uso"
    assert translate({"is invalid", []}) == "não é válido"
    assert translate({"has invalid format", []}) == "está num formato inválido"
    assert translate({"does not match confirmation", []}) == "não confere com a confirmação"
  end

  test "traduz os limites de tamanho, com singular e plural" do
    assert translate({"should be at least %{count} character(s)", [count: 1]}) ==
             "precisa ter ao menos 1 caractere"

    assert translate({"should be at least %{count} character(s)", [count: 8]}) ==
             "precisa ter ao menos 8 caracteres"

    assert translate({"should be at most %{count} character(s)", [count: 160]}) ==
             "precisa ter no máximo 160 caracteres"
  end

  defp translate(error), do: CoreComponents.translate_error(error)
end
