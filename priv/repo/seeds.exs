# Popula o banco de desenvolvimento com um usuário de cada papel de acesso,
# duas bandas de exemplo com seus elencos, o catálogo de músicas, o repertório
# de cada banda e a agenda dos próximos dias.
#
#     mix run priv/repo/seeds.exs
#
# Rodar de novo não duplica nada: o usuário é procurado pelo e-mail, a banda
# pelo nome, o vínculo pelo par músico/banda, a música pelo título, o
# repertório pelo par banda/música e o evento pelo título entre os que ainda
# estão por vir — o que já existe fica como está, e só o que falta é criado. Para voltar exatamente ao estado descrito aqui,
# jogando fora o que o roteiro de testes mexeu, use `mix ecto.reset`.
#
# Todos entram em /login com a senha "senha123456".

alias ChurchBands.Accounts
alias ChurchBands.Bands
alias ChurchBands.LocalTime
alias ChurchBands.Repertoire
alias ChurchBands.Schedule

password = "senha123456"

# Os quatro primeiros são as personas de acesso do roteiro de testes: Pastor e
# os dois Líderes de Louvor têm acesso total, e a musicista não tem cargo global
# nenhum — ela é Líder de Banda só por liderar a Banda A. Os demais existem para
# as bandas terem elenco de verdade, com naipes e instrumentos variados.
#
# A Sofia fecha a lista porque é a **segunda** Líder de Banda sem acesso total, e
# ela lidera a Banda B **sem estar no elenco dela** (DT-15). São duas coisas que
# o roteiro precisava e não tinha: um líder que só lidera — para provar que
# liderar conta como participar sem desmontar o elenco de ninguém — e um segundo
# líder comum com banda própria, que é o que permite escrever "o líder de uma
# banda não mexe no set da outra" pelos dois lados, em vez de pelo avesso.
#
# O Marcos deixou de liderar a Banda B por causa disso, e continua aqui: são
# **duas** contas de acesso total além do Pastor, e é o que faz o roteiro poder
# rebaixar uma delas sem deixar o sistema sem ninguém que responda por ele.
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
  %{name: "Rafael Guitarrista", email: "rafael@churchbands.local", global_role: :member},
  %{name: "Sofia Tecladista", email: "sofia@churchbands.local", global_role: :member}
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
# O instrumento vem do catálogo (US 2.8), que a migration já deixa cadastrado —
# aqui ele é procurado pelo nome, e não digitado.
#
# A Banda B começa com a líder **sem vínculo** de propósito: é o estado "Líder
# de Banda ainda sem função", que a página do elenco cobra com um aviso. Os dois
# começos possíveis ficam representados sem precisar cadastrar nada na mão.
#
# E quem a lidera é a Sofia, **musicista sem cargo global** — não um Líder de
# Louvor. Um líder com acesso total passa em qualquer verificação de permissão
# por banda sem provar nada: era isso que deixava as duas bandas sem um par de
# líderes comuns para exercitar "cada um responde pela sua" (DT-15).
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
    leader: "sofia@churchbands.local",
    members: [
      {"igor@churchbands.local", %{type: :instrumentalist, instrument: "Bateria"}},
      {"rafael@churchbands.local", %{type: :instrumentalist, instrument: "Guitarra"}},
      {"julia@churchbands.local", %{type: :vocalist, voice_part: "Soprano"}},
      {"lucas@churchbands.local", %{type: :vocalist, voice_part: "Baixo"}}
    ]
  }
]

# O catálogo de instrumentos nasce com a migration (US 2.8), então aqui basta
# trocar o nome pelo id. Nome fora do catálogo é erro do seed, não dado a
# cadastrar: quebrar alto é melhor do que gravar um vínculo sem instrumento.
instruments = Map.new(Bands.list_instruments(), &{&1.name, &1.id})

with_instrument_id = fn
  %{instrument: name} = attrs ->
    attrs
    |> Map.delete(:instrument)
    |> Map.put(:instrument_id, Map.fetch!(instruments, name))

  attrs ->
    attrs
end

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
    member_attrs = with_instrument_id.(member_attrs)

    if MapSet.member?(vinculados, user.id) do
      IO.puts("Integrante já vinculado: #{user.name} na #{band.name}")
    else
      {:ok, member} = Bands.add_member(band, user.id, member_attrs)
      IO.puts("Integrante vinculado: #{member.user.name} na #{band.name}")
    end
  end
end

# Catálogo de músicas (US 2.1). O cenário do roteiro precisa de três coisas
# visíveis de uma vez: música completa, música só com título e um par de
# títulos parecidos — "Grande é o Senhor" e "Grande e o Senhor" existem juntas
# de propósito, para que o aviso de duplicata tenha o que mostrar sem ninguém
# precisar cadastrar nada antes.
seed_songs = [
  %{
    title: "Grande é o Senhor",
    artist: "Adhemar de Campos",
    bpm: 72,
    reference_url: "https://www.youtube.com/results?search_query=grande+e+o+senhor",
    chord_chart_url: "https://www.cifraclub.com.br/adhemar-de-campos/grande-e-o-senhor/"
  },
  %{
    title: "Grande e o Senhor",
    artist: "Cadastro em duplicidade, de propósito",
    bpm: nil,
    reference_url: nil,
    chord_chart_url: nil
  },
  %{
    title: "Oceanos",
    artist: "Hillsong United",
    bpm: 68,
    reference_url: "https://www.youtube.com/results?search_query=oceanos+hillsong",
    chord_chart_url: nil
  },
  %{
    title: "Ousado Amor",
    artist: "Isaias Saad",
    bpm: 70,
    reference_url: nil,
    chord_chart_url: "https://www.cifraclub.com.br/isaias-saad/ousado-amor/"
  },
  %{title: "Aleluia", artist: nil, bpm: nil, reference_url: nil, chord_chart_url: nil}
]

# As tags de cada música (US 2.7). O cenário do roteiro precisa de tags em três
# situações ao mesmo tempo: em mais de uma música — para a exclusão ser recusada
# —, em uma só e em nenhuma. Sai daqui: Louvor e Adoração ficam em duas músicas
# cada, Celebração em uma, e as outras quatro em nenhuma.
seed_song_tags = %{
  "Grande é o Senhor" => ["Louvor", "Adoração"],
  "Oceanos" => ["Adoração"],
  "Ousado Amor" => ["Louvor"],
  "Aleluia" => ["Celebração"]
}

tags_by_name = Map.new(Repertoire.list_tags(), &{&1.name, &1})

existing_songs = Repertoire.list_songs()

for attrs <- seed_songs do
  song =
    case Enum.find(existing_songs, &(&1.title == attrs.title)) do
      nil ->
        {:ok, song} = Repertoire.create_song(attrs)
        IO.puts("Música cadastrada: #{song.title}")
        song

      song ->
        IO.puts("Música já existe: #{song.title}")
        song
    end

  # As tags são remarcadas a cada execução, e não só no cadastro: quem rodou os
  # seeds antes da US 2.7 tem as músicas sem tag nenhuma. Tag renomeada ou
  # excluída na tela simplesmente não é encontrada aqui, e o roteiro segue com
  # o que sobrou — os seeds não desfazem o que alguém testou.
  marcadas =
    seed_song_tags
    |> Map.get(song.title, [])
    |> Enum.flat_map(&List.wrap(tags_by_name[&1]))

  if marcadas != [] do
    {:ok, _song} = Repertoire.update_song(song, %{"tag_ids" => Enum.map(marcadas, & &1.id)})
    IO.puts("Música marcada: #{song.title} — #{Enum.map_join(marcadas, ", ", & &1.name)}")
  end
end

# O repertório das bandas (US 2.2 e 2.6). **A Banda A nasce com repertório e a
# Banda B nasce vazia**, de propósito: é o estado vazio da tela — "Nenhuma música
# no repertório ainda" — que o roteiro precisa ver sem criar banda nenhuma.
#
# **Os três status nascem representados**, um em cada música da Banda A, porque o
# filtro da US 2.6 não tem o que filtrar sem eles — e nenhuma tela arquiva música
# ainda, isso é a US 2.3. É a mesma razão de os seeds existirem: montar à mão o
# cenário que o roteiro precisa encontrar pronto. Repare que, no estado padrão da
# tela, "Ousado Amor" **não aparece**: arquivada é o que se tirou da frente.
#
# A mesma música em duas bandas, que é o que prova que o tom é da banda e não da
# música, **não vem daqui**: quem a cria é o próprio roteiro, vinculando "Grande
# é o Senhor" à Banda B num tom diferente do da A. É o mesmo gesto que a história
# entrega, e ele deixa a recusa de exclusão nomeando duas bandas e o "2 bandas"
# da coluna do catálogo como consequência do teste, não como dado plantado.
#
# "Aleluia" e "Grande e o Senhor" ficam fora de todo repertório: são as músicas
# que o roteiro exclui sem ser recusado, e as que mostram "Nenhuma banda" na
# coluna do catálogo.
seed_repertoire = %{
  "Banda A" => [
    {"Grande é o Senhor", "D", :learning},
    {"Oceanos", "G", :ready},
    {"Ousado Amor", "E", :archived}
  ]
}

songs_by_title = Map.new(Repertoire.list_songs(), &{&1.title, &1})

for band <- Bands.list_bands(), entries = seed_repertoire[band.name], entries do
  # `:all` porque o que interessa aqui é "esta música já está vinculada?", e a
  # arquivada está — o padrão da tela a esconderia, e o seed tentaria criá-la de
  # novo a cada execução.
  no_repertorio =
    band
    |> Repertoire.list_band_repertoire(%{status: :all})
    |> MapSet.new(& &1.song_id)

  for {title, key, status} <- entries, song = songs_by_title[title] do
    if MapSet.member?(no_repertorio, song.id) do
      IO.puts("Música já no repertório: #{song.title} na #{band.name}")
    else
      {:ok, entry} = Repertoire.add_song_to_band(band, song.id, %{key: key, status: status})

      IO.puts(
        "Música no repertório: #{entry.song.title} na #{band.name}, " <>
          "em #{entry.key} (#{entry.status})"
      )
    end
  end
end

# A agenda da igreja (US 3.2 a 3.5). Sem ela o calendário nasce vazio, e as
# telas que só leem — a grade mensal da US 3.3 e o bloco "Meus próximos
# eventos" da US 3.5 — não têm o que mostrar antes de alguém marcar evento na
# mão. É a mesma razão do repertório acima: montar o cenário que o roteiro
# precisa encontrar pronto.
#
# **As datas são relativas ao dia em que o seed roda**, e não fixas. Marcar
# evento exige data futura (`Event.creation_changeset/2`), então data escrita à
# mão envelheceria: o banco recriado no mês seguinte nasceria recusando o
# próprio seed.
#
# **Os três tipos nascem representados**, porque o filtro por tipo da US 3.3
# não tem o que filtrar sem eles. E um dos eventos nasce **cancelado**, que é o
# que a grade mostra riscado (3.3-J) e o portal também — vê-lo exigiria
# cancelar um evento antes.
#
# **A escala vem junto** (US 3.4): é ela que faz o bloco do portal responder
# alguma coisa a quem toca, e é ela que representa o que os seeds já dizem em
# outro lugar — a Sofia lidera a Banda B sem estar no elenco dela, e o culto da
# manhã aparecendo na tela dela é liderar contando como participar.
#
# A escala é desigual **de propósito**: a confraternização não tem banda
# nenhuma, porque zero banda é estado válido e não tela pela metade, e o culto
# de aniversário fica a 40 dias — fora da janela de 30 do portal —, para que o
# recorte de tempo se veja sem ninguém marcar nada.
#
# **O set não vem daqui** (US 3.6). Montá-lo é o gesto que a história entrega, e
# o primeiro caso dela começa com o set vazio: plantá-lo aqui tiraria do
# roteiro justamente o que ele tem para fazer. É a mesma razão de a segunda
# banda da mesma música não vir dos seeds, lá em cima.
hoje = LocalTime.today()

# `Date.day_of_week/1` conta de 1 (segunda) a 7 (domingo). A próxima ocorrência
# é sempre **depois** de hoje, e nunca hoje: o ensaio de hoje às 20h já teria
# passado para quem roda o seed às 22h, e marcar no passado é recusado.
next_weekday = fn weekday ->
  Date.add(hoje, Enum.find(1..7, &(Date.day_of_week(Date.add(hoje, &1)) == weekday)))
end

seed_events = [
  %{
    title: "Ensaio da Banda A",
    type: "Ensaio",
    date: next_weekday.(4),
    time: ~T[20:00:00],
    location: "Sala de música",
    notes: nil,
    status: :scheduled,
    bands: ["Banda A"]
  },
  %{
    title: "Ensaio da Banda B",
    type: "Ensaio",
    date: next_weekday.(5),
    time: ~T[20:00:00],
    location: "Sala de música",
    notes: nil,
    status: :cancelled,
    bands: ["Banda B"]
  },
  %{
    title: "Confraternização das bandas",
    type: "Confraternização",
    date: next_weekday.(6),
    time: ~T[16:00:00],
    location: "Salão social",
    notes: "Cada família leva um prato para dividir.",
    status: :scheduled,
    bands: []
  },
  %{
    title: "Culto da Manhã",
    type: "Culto",
    date: next_weekday.(7),
    time: ~T[09:00:00],
    location: "Templo sede",
    notes: nil,
    status: :scheduled,
    bands: ["Banda B"]
  },
  %{
    title: "Culto da Noite",
    type: "Culto",
    date: next_weekday.(7),
    time: ~T[19:00:00],
    location: "Templo sede",
    notes: nil,
    status: :scheduled,
    bands: ["Banda A"]
  },
  %{
    title: "Culto de aniversário da igreja",
    type: "Culto",
    date: Date.add(hoje, 40),
    time: ~T[19:00:00],
    location: "Templo sede",
    notes: nil,
    status: :scheduled,
    bands: ["Banda A"]
  }
]

# Os dois cultos de domingo, às 9h e às 19h, são o par que a janela de conflito
# de 3 horas da US 3.4 precisa deixar passar — e cada um tem a sua banda, que é
# o que faz o bloco do portal ser diferente para quem toca na A e para quem
# toca na B.

event_types_by_name = Map.new(Schedule.list_event_types(), &{&1.name, &1})
bands_by_name = Map.new(Bands.list_bands(), &{&1.name, &1})

# O evento é procurado **pelo título, entre os que ainda estão por vir** — e não
# pela data, que muda a cada execução. O que já passou fica onde está: é
# histórico, e repor o ensaio da semana passada não ajudaria ninguém. A janela
# de 60 dias é a que o seed planta, com folga para o culto de aniversário.
upcoming_events =
  [from: LocalTime.now(), to: DateTime.add(LocalTime.now(), 60, :day)]
  |> Schedule.list_events()
  |> Map.new(&{&1.title, &1})

for attrs <- seed_events do
  event =
    case upcoming_events[attrs.title] do
      nil ->
        {:ok, event} =
          Schedule.create_event(%{
            event_type_id: Map.fetch!(event_types_by_name, attrs.type).id,
            title: attrs.title,
            starts_at_local: NaiveDateTime.new!(attrs.date, attrs.time),
            location: attrs.location,
            notes: attrs.notes
          })

        IO.puts("Evento marcado: #{event.title}, #{LocalTime.format(event.starts_at, :short)}")

        # Cancelar acontece **só no cadastro**, e não a cada execução: reabrir é
        # gesto do roteiro (3.2-H), e recancelar por baixo desfaria o que
        # alguém acabou de testar — o mesmo cuidado das tags lá em cima.
        if attrs.status == :cancelled do
          {:ok, cancelled} = Schedule.cancel_event(event)
          IO.puts("Evento cancelado: #{cancelled.title}")
          cancelled
        else
          event
        end

      event ->
        IO.puts("Evento já existe: #{event.title}, #{LocalTime.format(event.starts_at, :short)}")
        event
    end

  escaladas = event |> Schedule.list_event_bands() |> MapSet.new(& &1.band_id)

  for name <- attrs.bands do
    band = Map.fetch!(bands_by_name, name)

    if MapSet.member?(escaladas, band.id) do
      IO.puts("Banda já escalada: #{band.name} em #{event.title}")
    else
      {:ok, _event_band} = Schedule.schedule_band(event, band.id)
      IO.puts("Banda escalada: #{band.name} em #{event.title}")
    end
  end
end
