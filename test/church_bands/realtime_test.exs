defmodule ChurchBands.RealtimeTest do
  @moduledoc """
  Os tópicos são só string — o teste garante que as duas formas de chamar
  cada função (a struct e o id nu) chegam na **mesma** string, porque é essa
  igualdade que faz quem publica e quem assina se encontrarem.
  """
  use ExUnit.Case, async: true

  alias ChurchBands.Accounts.User
  alias ChurchBands.Bands.Band
  alias ChurchBands.Bands.BandMember
  alias ChurchBands.Realtime
  alias ChurchBands.Repertoire.BandRepertoire
  alias ChurchBands.Schedule.Event
  alias ChurchBands.Schedule.EventBand
  alias ChurchBands.Schedule.EventBandSong

  describe "notifications_topic/1" do
    test "struct e id nu chegam na mesma string" do
      assert Realtime.notifications_topic(%User{id: 7}) == "notifications:user:7"
      assert Realtime.notifications_topic(7) == "notifications:user:7"
    end
  end

  describe "event_topic/1" do
    test "struct e id nu chegam na mesma string" do
      assert Realtime.event_topic(%Event{id: 9}) == "events:9"
      assert Realtime.event_topic(9) == "events:9"
    end
  end

  describe "event_band_topic/1" do
    test "event_band, event_band_song e id nu chegam na mesma string" do
      assert Realtime.event_band_topic(%EventBand{id: 3}) == "event_bands:3"
      assert Realtime.event_band_topic(%EventBandSong{event_band_id: 3}) == "event_bands:3"
      assert Realtime.event_band_topic(3) == "event_bands:3"
    end
  end

  describe "calendar_topic/0" do
    test "não tem id — é a grade inteira" do
      assert Realtime.calendar_topic() == "calendar"
    end
  end

  describe "band_topic/1" do
    test "struct, membro e id nu chegam na mesma string" do
      assert Realtime.band_topic(%Band{id: 11}) == "bands:11"
      assert Realtime.band_topic(%BandMember{band_id: 11}) == "bands:11"
      assert Realtime.band_topic(11) == "bands:11"
    end
  end

  describe "band_repertoire_topic/1" do
    test "struct, entrada de repertório e id nu chegam na mesma string" do
      assert Realtime.band_repertoire_topic(%Band{id: 4}) == "band_repertoire:4"
      assert Realtime.band_repertoire_topic(%BandRepertoire{band_id: 4}) == "band_repertoire:4"
      assert Realtime.band_repertoire_topic(4) == "band_repertoire:4"
    end
  end

  describe "subscribe/1 e broadcast/2" do
    test "quem assina recebe a mensagem, e ninguém mais escuta por engano" do
      topic = Realtime.event_topic(999)

      :ok = Realtime.subscribe(topic)
      Realtime.broadcast(topic, :event_updated)

      assert_receive :event_updated

      Realtime.broadcast(Realtime.event_topic(1000), :event_updated)
      refute_receive :event_updated, 50
    end
  end
end
