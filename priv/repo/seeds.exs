# Popula o banco de desenvolvimento com um usuário de cada papel de acesso e
# duas bandas de exemplo, cada uma com seu elenco.
#
#     mix run priv/repo/seeds.exs
#
# Rodar de novo não duplica nada: o usuário é procurado pelo e-mail, a banda
# pelo nome e o vínculo pelo par músico/banda — o que já existe fica como está,
# e só o que falta é criado. Para voltar exatamente ao estado descrito aqui,
# jogando fora o que o roteiro de testes mexeu, use `mix ecto.reset`.
#
# Todos entram em /login com a senha "senha123456".

alias ChurchBands.Accounts
alias ChurchBands.Bands

password = "senha123456"

# Os três primeiros são as personas de acesso do roteiro de testes: Pastor e
# Líder de Louvor têm acesso total, e a musicista não tem cargo global nenhum —
# ela é Líder de Banda só por liderar a Banda A. Os demais existem para as
# bandas terem elenco de verdade, com naipes e instrumentos variados.
seed_users = [
  %{name: "André Pastor", email: "pastor@churchbands.local", global_role: :pastor},
  %{
    name: "Bruno Líder de Louvor",
    email: "louvor@churchbands.local",
    global_role: :worship_leader
  },
  %{name: "Carla Musicista", email: "musica@churchbands.local", global_role: :member},
  %{
    name: "Marcos Líder de Louvor",
    email: "louvor2@churchbands.local",
    global_role: :worship_leader
  },
  %{name: "Elias Guitarrista", email: "elias@churchbands.local", global_role: :member},
  %{name: "Fábio Baixista", email: "fabio@churchbands.local", global_role: :member},
  %{name: "Gabriela Vocalista", email: "gabriela@churchbands.local", global_role: :member},
  %{name: "Helena Vocalista", email: "helena@churchbands.local", global_role: :member},
  %{name: "Igor Baterista", email: "igor@churchbands.local", global_role: :member},
  %{name: "Júlia Vocalista", email: "julia@churchbands.local", global_role: :member},
  %{name: "Lucas Vocalista", email: "lucas@churchbands.local", global_role: :member},
  %{name: "Rafael Guitarrista", email: "rafael@churchbands.local", global_role: :member}
]

for attrs <- seed_users do
  case Accounts.get_user_by_email(attrs.email) do
    nil ->
      {:ok, user} =
        attrs
        |> Map.merge(%{
          password: password,
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Accounts.create_user()

      IO.puts("Usuário criado: #{user.email} (#{user.global_role})")

    user ->
      IO.puts("Usuário já existe: #{user.email}")
  end
end

# Duas bandas de exemplo. O papel "Líder de Banda" nasce aqui, pelo vínculo em
# `bands.leader_id`, e não por um `global_role`: é por isso que a Carla lidera a
# Banda A sendo apenas musicista.
#
# O elenco (US 1.4) mostra que o mesmo usuário tem função própria em cada banda:
# a líder da Banda A toca violão nela, e o Líder de Louvor canta.
#
# A Banda B começa com o líder **sem vínculo** de propósito: é o estado "Líder
# de Banda ainda sem função", que a página do elenco cobra com um aviso. Os dois
# começos possíveis ficam representados sem precisar cadastrar nada na mão.
seed_bands = [
  %{
    name: "Banda A",
    description: "Toca no culto de domingo à noite.",
    leader: "musica@churchbands.local",
    members: [
      {"musica@churchbands.local", %{type: :instrumentalist, instrument: "Violão"}},
      {"elias@churchbands.local", %{type: :instrumentalist, instrument: "Guitarra"}},
      {"fabio@churchbands.local", %{type: :instrumentalist, instrument: "Baixo"}},
      {"louvor@churchbands.local", %{type: :vocalist, voice_part: "Tenor"}},
      {"gabriela@churchbands.local", %{type: :vocalist, voice_part: "Soprano"}},
      {"helena@churchbands.local", %{type: :vocalist, voice_part: "Contralto"}}
    ]
  },
  %{
    name: "Banda B",
    description: "Toca no culto de domingo pela manhã.",
    leader: "louvor2@churchbands.local",
    members: [
      {"igor@churchbands.local", %{type: :instrumentalist, instrument: "Bateria"}},
      {"rafael@churchbands.local", %{type: :instrumentalist, instrument: "Guitarra"}},
      {"julia@churchbands.local", %{type: :vocalist, voice_part: "Soprano"}},
      {"lucas@churchbands.local", %{type: :vocalist, voice_part: "Baixo"}}
    ]
  }
]

existing_bands = Bands.list_bands()

for attrs <- seed_bands do
  band =
    case Enum.find(existing_bands, &(String.downcase(&1.name) == String.downcase(attrs.name))) do
      nil ->
        leader = Accounts.get_user_by_email(attrs.leader)

        {:ok, band} =
          Bands.create_band(%{
            name: attrs.name,
            description: attrs.description,
            leader_id: leader.id
          })

        IO.puts("Banda criada: #{band.name} (líder: #{band.leader.name})")
        band

      band ->
        IO.puts("Banda já existe: #{band.name}")
        band
    end

  vinculados = band |> Bands.list_members() |> MapSet.new(& &1.user_id)

  for {email, member_attrs} <- attrs.members do
    user = Accounts.get_user_by_email(email)

    if MapSet.member?(vinculados, user.id) do
      IO.puts("Integrante já vinculado: #{user.name} na #{band.name}")
    else
      {:ok, member} = Bands.add_member(band, user.id, member_attrs)
      IO.puts("Integrante vinculado: #{member.user.name} na #{band.name}")
    end
  end
end
