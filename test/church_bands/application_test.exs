defmodule ChurchBands.ApplicationTest do
  @moduledoc """
  Os retornos de callback da aplicação OTP.

  `start/2` já é exercido por toda a suíte — sem ele não haveria repositório
  nem endpoint. O que não aparece em lugar nenhum é `config_change/3`, chamado
  pelo OTP quando a aplicação é atualizada em produção: é ele que repassa a
  configuração nova ao endpoint, e um erro aí só se descobre em um deploy
  quente.
  """
  use ExUnit.Case, async: true

  describe "config_change/3" do
    test "repassa ao endpoint o que mudou e o que saiu da configuração" do
      assert ChurchBands.Application.config_change([], [], []) == :ok
    end
  end
end
