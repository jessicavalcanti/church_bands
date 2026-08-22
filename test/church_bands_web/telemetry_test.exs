defmodule ChurchBandsWeb.TelemetryTest do
  @moduledoc """
  As métricas que a aplicação publica.

  A lista alimenta os relatores da árvore de supervisão e o LiveDashboard, e um
  nome de evento escrito errado só apareceria em produção, na forma de um painel
  vazio. O prefixo do repositório é o que mais convida ao engano: ele vem do
  nome da aplicação (`church_bands`), não do nome do módulo.
  """
  use ExUnit.Case, async: true

  alias ChurchBandsWeb.Telemetry

  describe "metrics/0" do
    test "publica métricas de Phoenix, do repositório e da VM" do
      nomes = Enum.map(Telemetry.metrics(), &Enum.join(&1.name, "."))

      assert "phoenix.endpoint.stop.duration" in nomes
      assert "phoenix.router_dispatch.stop.duration" in nomes
      assert "church_bands.repo.query.total_time" in nomes
      assert "vm.memory.total" in nomes
    end

    test "mede o tempo das consultas em milissegundos" do
      metrica = metrica("church_bands.repo.query.query_time")

      assert metrica.unit == :millisecond
    end

    test "separa o despacho de rotas por rota" do
      metrica = metrica("phoenix.router_dispatch.stop.duration")

      assert metrica.tags == [:route]
    end
  end

  describe "init/1" do
    test "supervisiona o poller que coleta as medições periódicas" do
      assert {:ok, {_flags, [poller]}} = Telemetry.init(:ok)

      assert poller.id == :telemetry_poller
    end
  end

  defp metrica(nome) do
    Enum.find(Telemetry.metrics(), &(Enum.join(&1.name, ".") == nome))
  end
end
