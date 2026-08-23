defmodule ChurchBands.RouteId do
  @moduledoc """
  O id que chega pelos parâmetros de rota é texto, e pode ser **qualquer**
  texto: quem digita na barra de endereços escreve o que quiser.
  """

  @doc """
  Chama `get` com `id` convertido para inteiro, ou devolve `nil` quando o que
  veio na rota não é um id.

  Devolver `nil` é o ponto: as telas já sabem lidar com "não encontrado" e
  mostram a mesma recusa para o id inventado e para o que não existe mais —
  bem melhor do que uma página de erro por um `Ecto.Query.CastError`.

      def get_user(id) when is_binary(id), do: RouteId.get(id, &get_user/1)
  """
  def get(id, get) when is_binary(id) and is_function(get, 1) do
    case Integer.parse(id) do
      {id, ""} -> get.(id)
      _ -> nil
    end
  end
end
