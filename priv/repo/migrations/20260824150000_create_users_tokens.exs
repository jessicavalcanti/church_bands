defmodule ChurchBands.Repo.Migrations.CreateUsersTokens do
  use Ecto.Migration

  # A tabela de tokens do `phx.gen.auth` (DT-12). Até aqui a sessão era o id do
  # usuário mais uma impressão digital da senha, dentro do cookie: derrubava
  # tudo na troca de senha, mas não sabia dizer quantas sessões existiam nem
  # apagar uma delas.
  #
  # Duas colunas do gerador ficaram de fora, e é de propósito:
  #
  #   * `sent_to` serve aos tokens que viajam por e-mail — link mágico e troca
  #     de endereço. Este projeto não os tem, e a recuperação de senha (US 1.7)
  #     tem tabela própria, com hash e uso único
  #   * `authenticated_at` serve ao "sudo mode" do Phoenix 1.8, que pede a senha
  #     de novo antes de uma ação sensível. Também não existe aqui
  #
  # `context` fica, com o índice único do gerador: é ela que permite a tabela
  # crescer para os outros usos sem virar outra tabela.
  def change do
    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
