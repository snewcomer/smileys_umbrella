defmodule SmileysWeb.RoomChannel do
  use Phoenix.Channel
  import Guardian.Phoenix.Socket

  alias SmileysWeb.{Presence}

  require Logger


  def join("room:" <> _room_name, %{"guardian_token" => token}, socket) do
    case sign_in(socket, token) do
      {:ok, authed_socket, _guardian_params} ->
        send(self(), {:after_join, nil})

        {:ok, %{result: "Joined"}, authed_socket}
      {:error, _reason} ->
        Logger.error "Auth error, expected token to auth user"
    end
  end
  
  # Readonly still allowed if no token
  def join("room:" <> _room_name, %{"mystery_token" => mystery_token}, socket) do
    send(self(), {:after_join, mystery_token})

    {:ok, %{result: "Joined"}, socket}
  end

  def join("room:" <> _room_name, _message, socket) do
    send(self(), {:after_join, nil})

    {:ok, %{result: "Joined"}, socket}
  end


  def handle_info({:after_join, mystery_token}, socket) do
    user = case current_resource(socket) do
      nil ->
        %{id: mystery_token}
      logged_in_user ->
        logged_in_user
    end
  
    if (user.id) do
      push socket, "presence_state", Presence.list(socket)
      {:ok, _} = Presence.track(socket, user.id, %{
        online_at: inspect(System.system_time(:seconds))
      })
    end
    {:noreply, socket}
  end

  def handle_in("voteup", %{"posthash" => hash, "room" => room_name}, socket) do 
    user = current_resource(socket)

    post = SmileysData.QueryPost.post_by_hash(hash)

    result_vote = case user do
      nil ->
        {:no_user, 0}
      _ ->
        post_user = SmileysData.QueryUser.user_by_id(post.posterid)
        Smileys.Vote.Action.upvote(post, user, post_user, room_name)
    end
    
    _vote = case result_vote do
      {:ok, amount} ->
        SmileysWeb.Endpoint.broadcast("post:" <> post.hash, "vote", %{posthash: hash, score: (post.votepublic + amount), result: amount, type: "up"})
        SmileysWeb.Endpoint.broadcast("user:" <> user.name, "vote", %{direction: "up", hash: hash})
        SmileysWeb.Endpoint.broadcast("room:" <> room_name, "vote", %{posthash: hash, score: (post.votepublic + amount), result: amount, type: "up"})
        SmileysWeb.Endpoint.broadcast("room:all", "vote", %{direction: "up", hash: hash})
        amount
      {:no_vote, amount} ->
        SmileysWeb.Endpoint.broadcast("user:" <> user.name, "warning", %{msg: "Votes are final and one per post"})
        amount
      {:vote_time_over, amount} ->
        SmileysWeb.Endpoint.broadcast("user:" <> user.name, "warning", %{msg: "Voting closed; voting lasts for 3 days"})
        amount
      _ ->
        0
    end

    {:noreply, socket}
  end

  def handle_in("votedown", %{"posthash" => hash, "room" => room_name}, socket) do 
    user = current_resource(socket)

    post = SmileysData.QueryPost.post_by_hash(hash)

    result_vote = case user do
      nil ->
        {:no_user, 0}
      _ ->
        post_user = SmileysData.QueryUser.user_by_id(post.posterid)
        Smileys.Vote.Action.downvote(post, user, post_user, room_name)
    end

    _vote = case result_vote do
      {:ok, amount} ->
        SmileysWeb.Endpoint.broadcast("post:" <> post.hash, "vote", %{posthash: hash, score: (post.votepublic + amount), result: amount, type: "down"})
        SmileysWeb.Endpoint.broadcast("user:" <> user.name, "vote", %{direction: "up", hash: hash})
        SmileysWeb.Endpoint.broadcast("room:" <> room_name, "vote", %{posthash: hash, score: (post.votepublic + amount), result: amount, type: "down"})
        SmileysWeb.Endpoint.broadcast("room:all", "vote", %{direction: "down", hash: hash})
        amount
      {:no_vote, amount} ->
        SmileysWeb.Endpoint.broadcast("user:" <> user.name, "warning", %{msg: "Votes are final and one per post"})
        amount
      {:vote_time_over, amount} ->
        SmileysWeb.Endpoint.broadcast("user:" <> user.name, "warning", %{msg: "Voting closed; voting lasts for 3 days"})
        amount
      _ ->
        0
    end

    {:noreply, socket}
  end

  # Accept events from an external app within the umbrella
  def handle_in("activity_external", %{"room" => room_name, "activity" => activity}) do
    SmileysWeb.Endpoint.broadcast("room:" <> room_name, "activity", activity)
  end
end