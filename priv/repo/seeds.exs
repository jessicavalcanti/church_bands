# Popula o banco de desenvolvimento com um usuário de cada papel de acesso e
# uma banda de exemplo.
#
#     mix run priv/repo/seeds.exs
#
# Todos entram em /login com a senha "senha123456".

alias ChurchBands.Accounts
alias ChurchBands.Bands

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

# Uma banda de exemplo, liderada pela musicista — é assim que o papel "Líder de
# Banda" nasce: pelo vínculo em `bands.leader_id`, não por um `global_role`.
case Bands.list_bands() do
  [] ->
    leader = Accounts.get_user_by_email("musica@churchbands.local")

    {:ok, band} =
      Bands.create_band(%{
        name: "Banda Jovem",
        description: "Toca no culto de domingo à noite.",
        leader_id: leader.id
      })

    IO.puts("Banda criada: #{band.name} (líder: #{band.leader.name})")

    # Elenco de exemplo (US 1.4): a própria líder toca, e o Líder de Louvor
    # canta — o mesmo usuário pode ter funções diferentes em cada banda.
    seed_members = [
      {leader, %{type: :instrumentalist, instrument: "Violão"}},
      {Accounts.get_user_by_email("louvor@churchbands.local"),
       %{type: :vocalist, voice_part: "Tenor"}}
    ]

    for {user, attrs} <- seed_members do
      {:ok, member} = Bands.add_member(band, user.id, attrs)
      IO.puts("Integrante vinculado: #{member.user.name} na #{band.name}")
    end

  bands ->
    IO.puts("Bandas já cadastradas: #{Enum.map_join(bands, ", ", & &1.name)}")
end
