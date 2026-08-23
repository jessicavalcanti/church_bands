defmodule ChurchBands.Sorting do
  @moduledoc """
  Ordem alfabética de listas escritas em português.

  Existe porque **`ORDER BY name` não é ordem alfabética**: quem ordena no
  PostgreSQL é a collation, e ela muda com o locale de quem subiu o banco. Numa
  máquina com `pt_BR.UTF-8`, "Ângela" cai entre "André" e "Bruno"; num container
  sem locale instalado — o do CI e o da imagem de produção — a comparação vira
  byte a byte, o `Â` vale mais que qualquer letra sem acento e ela vai parar
  depois do "Z". A mesma lista aparecia em ordens diferentes conforme o
  ambiente, e nenhum teste pegava isso porque os dois lados achavam que estavam
  certos.

  Ordenar em Elixir sem tratar o texto tem o mesmo defeito por outro caminho:
  `Enum.sort/1` compara codepoints, e o acento continua valendo mais.

  A chave decompõe o texto em NFD e joga fora as marcas combinantes, que é como
  um leitor brasileiro lê uma lista: "angela" entre "andre" e "bruno", "violao"
  antes de "violino". O resultado é o mesmo em todo ambiente, porque não depende
  de mais nada.

  As listas do sistema são de dezenas de linhas — ordenar em memória não é o
  custo que se está economizando com um `ORDER BY`.
  """

  @doc """
  Ordena por `.name`, alfabeticamente.
  """
  def by_name(records), do: Enum.sort_by(records, &key(&1.name))

  @doc """
  A chave de ordenação de um texto: minúsculas, sem acento.

  Para quem ordena por mais de um critério — o elenco, que é por função e
  depois por nome — e monta a própria tupla.
  """
  def key(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
  end
end
