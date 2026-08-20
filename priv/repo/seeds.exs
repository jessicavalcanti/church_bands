# Popula o banco de desenvolvimento com um usuário de cada papel de acesso.
#
#     mix run priv/repo/seeds.exs
#
# Todos entram em /login com a senha "senha123456".

alias ChurchBands.Accounts

seed_users = [
  %{
    name: "Ana Pastora",
    email: "pastora@churchbands.local",
    password: "senha123456",
    global_role: :pastor
  },
  %{
    name: "Bruno Líder de Louvor",
    email: "louvor@churchbands.local",
    password: "senha123456",
    global_role: :worship_leader
  },
  %{
    name: "Carla Musicista",
    email: "musica@churchbands.local",
    password: "senha123456",
    global_role: :member
  }
]

for attrs <- seed_users do
  case Accounts.get_user_by_email(attrs.email) do
    nil ->
      {:ok, user} =
        attrs
        |> Map.put(:confirmed_at, DateTime.utc_now() |> DateTime.truncate(:second))
        |> Accounts.create_user()

      IO.puts("Usuário criado: #{user.email} (#{user.global_role})")

    user ->
      IO.puts("Usuário já existe: #{user.email}")
  end
end
