defmodule SmileysWeb.SearchChannel do
  use Phoenix.Channel

  require Logger


  def join("search:" <> _search_term, _message, socket) do
    {:ok, socket}
  end

  def handle_in("search_for", %{"term" => term, "offset" => offset}, socket) do

  	{search_results, amount} = case SmileysSearch.QueryPost.posts_all(term, offset) do
  		{:ok, results, amount_results} ->
  			{results, amount_results}
  		{:error, _} ->
  			{[], 0}
  	end

  	posts = SmileysData.QueryPost.post_summary_by_ids(search_results)

  	SmileysWeb.Endpoint.broadcast("search:" <> term, "search_result", %{results: posts, amt: amount})

    {:noreply, socket}
  end
end