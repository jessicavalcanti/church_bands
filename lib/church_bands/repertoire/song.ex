defmodule ChurchBands.Repertoire.Song do
  @moduledoc """
  Música do catálogo central (US 2.1).

  Só o título é obrigatório: artista, BPM e os dois links de referência são o
  que se tem em mãos na hora do cadastro, e cobrar qualquer um deles atrasaria
  o que a tela existe para fazer.

  **O título não é único.** Duas músicas com o mesmo nome podem coexistir — a
  tela avisa sobre as parecidas e quem cadastra decide. A regra e o porquê
  estão em `ChurchBands.Repertoire.find_similar_songs/2`.
  """
  use Ecto.Schema

  import ChurchBands.Changesets, only: [trim_change: 2]
  import Ecto.Changeset

  # O link é conferido pelo esquema, não pelo domínio inteiro: o que a tela
  # precisa garantir é que o endereço abra no navegador quando alguém clicar.
  @url_format ~r{^https?://}i
  @url_message "precisa começar com http:// ou https://"

  schema "songs" do
    field :title, :string
    field :artist, :string
    field :bpm, :integer
    field :reference_url, :string
    field :chord_chart_url, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset de cadastro e edição de música.

  O BPM não tem faixa de propósito: quem cadastra conhece o andamento melhor
  do que qualquer limite que estivesse escrito aqui. O que o campo recusa é
  valor que não seja número inteiro, e isso vem do tipo.
  """
  def changeset(song, attrs) do
    song
    |> cast(attrs, [:title, :artist, :bpm, :reference_url, :chord_chart_url])
    |> trim_change(:title)
    |> validate_required([:title], message: "informe o título da música")
    |> validate_length(:title, max: 255, message: "precisa ter no máximo 255 caracteres")
    |> validate_format(:reference_url, @url_format, message: @url_message)
    |> validate_format(:chord_chart_url, @url_format, message: @url_message)
  end
end
