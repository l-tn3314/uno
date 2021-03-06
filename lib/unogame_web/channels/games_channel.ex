defmodule UnogameWeb.GamesChannel do
  use UnogameWeb, :channel

  alias Unogame.Game
  alias Unogame.BackupAgent

  def join("games:" <> name, payload, socket) do
    if authorized?(payload) do
      playerid = payload["playerid"]
      game = BackupAgent.get(name) || Game.new()
      if Game.game_started?(game) do
        {:error, %{reason: "game already in progress"}}
      else
        game = game
        |> Game.join_game(playerid)

        socket = socket
        |> assign(:game, game)
        |> assign(:name, name)
        |> assign(:playerid, playerid)
      
        BackupAgent.put(name, game)

        if Game.is_ready?(game) do
          send(self(), :game_ready)
        end
        {:ok, %{"game" => Game.client_view(game)}, socket}
      end
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def terminate(_reason, socket) do
    playerid = socket.assigns[:playerid]
    name = socket.assigns[:name]
    game = BackupAgent.get(name)
    |> Game.leave_game(playerid)
    BackupAgent.put(name, game)
    broadcast(socket, "update_game", %{})
    {:noreply, socket}
  end

  def handle_info(:game_ready, socket) do
    name = socket.assigns[:name]
    game = socket.assigns[:game]
    |> Game.deal_cards
    BackupAgent.put(name, game)
    broadcast(socket, "game_ready", %{player_ids: game.player_ids})
    {:noreply, socket}
  end

  def handle_in("get_game", %{"playerid" => playerid}, socket) do
    name = socket.assigns[:name]
    game = BackupAgent.get(name)
    {:reply, {:ok, %{"game" => Game.client_view(game, playerid)}}, socket}
  end
  def handle_in("draw_card", %{"playerid" => playerid}, socket) do
    try do
      name = socket.assigns[:name]
      game = Game.draw_card(BackupAgent.get(name), playerid)
      socket = socket
      |> assign(:game, game)
      BackupAgent.put(name, game)
      broadcast(socket, "update_game", %{})
      {:reply, {:ok, %{"game" => Game.client_view(game, playerid)}}, socket}
    rescue
      e in ArgumentError -> {:reply, {:error, %{reason: e.message}}, socket}
    end
  end
  # card should be in the format of [color, value]
  def handle_in("play_card", %{"playerid" => playerid, "card" => card}, socket) do
    try do
      name = socket.assigns[:name]
      game = Game.play_card(BackupAgent.get(name), playerid, card)
      socket = socket
      |> assign(:game, game)
      BackupAgent.put(name, game)
      broadcast(socket, "update_game", %{})

      if Game.game_over?(game) do
        IO.puts("game over")
        BackupAgent.put(name, nil) # clear game from BackupAgent
        broadcast(socket, "game_over", %{})
      end
      {:reply, {:ok, %{"game" => Game.client_view(game, playerid)}}, socket}
    rescue
      e in ArgumentError -> {:reply, {:error, %{reason: e.message}}, socket}
    end
  end

  defp authorized?(_payload) do
    true
  end
end
