defmodule ChurchBands.FailingMailerAdapter do
  @moduledoc """
  Adapter do Swoosh que recusa toda entrega.

  O adapter de teste padrão sempre entrega, então sem este aqui não há como
  exercitar o que a aplicação faz quando o servidor de e-mail está fora do ar —
  e é justamente aí que o convite entra no banco sem que ninguém receba o link.

  Troque a configuração do `ChurchBands.Mailer` por ele dentro de um caso de
  teste **síncrono**, devolvendo a original no `on_exit/1`: a configuração é
  global e valeria para os testes rodando em paralelo.
  """
  @behaviour Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :servidor_de_email_fora_do_ar}

  @impl Swoosh.Adapter
  def validate_config(_config), do: :ok
end
