defmodule SmileysWeb.PageController do
  use SmileysWeb, :controller

  plug Smileys.Plugs.SetNewRooms, 5
  plug Smileys.Plugs.SetCanPost
  plug Smileys.Plugs.SetUser
  plug Smileys.Plugs.SetCanSubscribe
  plug Smileys.Plugs.SetUserSubscriptions
  plug Smileys.Plugs.SetUserActivity
  plug Smileys.Plugs.SetIsModerator

  alias SmileysData.State.Activity
  alias SmileysData.State.Post.Activity, as: PostActivity


  def index(conn, _params) do
    {posts, _} = SmileysData.QueryPost.summary(10)

    reputable_rooms = SmileysData.QueryRoom.list_by(:reputation, 5)

    render conn, "index.html", new_posts: decorate_post_comment_count(posts), reputable_rooms: reputable_rooms
  end

  def profile(conn, %{"username" => user_name} = _params) do
    case SmileysData.QueryUser.user_by_name(user_name) do
      %{name: _} = user ->
        posts = SmileysData.QueryPost.latest_by_user(user, 50, false)

        render conn, "profile.html", posts: posts, profileuser: user
      _ ->
        conn
          |> put_status(:not_found)
          |> render(SmileysWeb.ErrorView, "404.html")
    end
  end

  def settings(conn, %{"username" => user_name} = _params) do
    current_user = conn.assigns.user

    cond do
      current_user.name == user_name ->
        render conn, "settings.html"
      true ->
        conn
          |> put_status(401)
          |> render(SmileysWeb.ErrorView, "401.html")
    end
  end

  def house(conn, %{"room" => room_name} = _params) do
  	room = SmileysData.QueryRoom.room(room_name)

  	if !room do
  	  conn
	    |> put_status(:not_found)
	   	|> render(SmileysWeb.ErrorView, "404.html")
  	end

  	{posts, _} = case room_name do
  		"all" -> 
  		  SmileysData.QueryPost.summary(30)
  		"walloffame" ->
  		  SmileysData.QueryPost.summary(30, :alltime)
  		_ ->
  		  conn
  		  	|> put_status(:not_found)
  		  	|> render(Smileys.ErrorView, "404.html")
  	end

  	render conn, "house.html", room: room, posts: decorate_post_comment_count(posts), roomtype: "house"
  end

  def room(conn, %{"room" => room_name} = params) do
  	room = SmileysData.QueryRoom.room(room_name)

    current_user = conn.assigns.user

  	if !room do
  	  conn
	    |> put_status(:not_found)
	   	|> render(SmileysWeb.ErrorView, "404.html")
  	end

    {:ok, is_mod} = allowed_in_room(conn, current_user, room)

  	{posts, kerosene} = cond do
  		(params["mode"] && params["mode"] == "new") ->
	  		SmileysData.QueryPost.summary_by_room(25, :new, room.id, params)
  		true ->
		  	SmileysData.QueryPost.summary_by_room(25, :vote, room.id, params)
	  end

  	render conn, "room.html", room: room, posts: decorate_post_comment_count(posts), ismod: is_mod, roomtype: "room", kerosene: kerosene
  end

  def comments(conn, %{"room" => _room, "hash" => hash, "focushash" => focushash} = _params) do
    current_user = conn.assigns.user

  	post = SmileysData.QueryPost.post_by_hash(focushash)

  	op = SmileysData.QueryPost.post_by_hash(hash)

    roomData = SmileysData.QueryRoom.room_by_id(post.superparentid)

    parentpost = case post.parenttype do
      "room" ->
        nil
      _ ->
        SmileysData.QueryPost.post_by_id(post.parentid)
    end

    _ = allowed_in_room(conn, current_user, roomData)

  	original_poster = SmileysData.QueryUser.user_by_id(post.posterid)

  	comments = SmileysData.QueryPost.get_thread("focus", post.id)

  	render conn, "post.html", post: post, op: op, title: roomData.name, roomtype: "room", room: roomData, comments: comments, opname: original_poster.name, parent: parentpost, opmeta: nil
  end

  def comments(conn, %{"room" => _room, "hash" => hash} = params) do
    current_user = conn.assigns.user

  	post = SmileysData.QueryPost.post_by_hash(hash)

    if !post do
      conn 
        |> put_status(404) 
        |> render(SmileysWeb.ErrorView, "404.html")
    end

  	op = post

  	op_meta = SmileysData.QueryPostMeta.postmeta_by_post_id(op.id)

  	original_poster = SmileysData.QueryUser.user_by_id(post.posterid)

  	roomData = SmileysData.QueryRoom.room_by_id(post.superparentid)

    _ = allowed_in_room(conn, current_user, roomData)

  	{comments, mode} = cond do
  		params["mode"] && params["mode"] == "new" ->
  			{SmileysData.QueryPost.get_thread("new", post.id), "new"}
  	  true ->
  			{SmileysData.QueryPost.get_thread("hot", post.id), "hot"}
  	end

  	render conn, "post.html", post: post, op: op, title: roomData.name, mode: mode, roomtype: "room", room: roomData, comments: comments, opname: original_poster.name, opmeta: op_meta
  end

  def about(conn, _params) do
    render conn, "about.html"
  end

  def tos(conn, _params) do
    render conn, "tos.html"
  end

  defp decorate_post_comment_count(posts) do
    posts_decorated = Enum.map(posts, fn(post) ->
      %PostActivity{comments: comments} = Activity.retrieve_item(%PostActivity{hash: post.hash})

      Map.put(post, :comment_count, comments)
    end)

    posts_decorated
  end

  defp allowed_in_room(conn, current_user, room) do
    is_mod = cond do 
      Map.has_key?(conn.assigns, :user) && current_user ->
        SmileysData.QueryRoom.room_is_moderator(current_user, room.id)
      true ->
        false
    end

    # See if user has permission to view room
    if room.type == "private" do
      if !current_user do
        conn |> put_status(401) |> render(SmileysWeb.ErrorView, "401.html")
      else
        user_in_allow_list = case SmileysData.QueryUserRoomAllow.user_allowed_in_room(current_user.name, room.name) do
          {:user_not_allowed, _} ->
            false
          _ ->
            true
        end

        if !is_mod && !user_in_allow_list do
          conn 
            |> put_status(401) 
            |> render(SmileysWeb.ErrorView, "401.html")
        end
      end
    end

    {:ok, is_mod}
  end
end

