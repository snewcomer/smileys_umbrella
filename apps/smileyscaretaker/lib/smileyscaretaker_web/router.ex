defmodule SmileyscaretakerWeb.Router do
  use SmileyscaretakerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SmileyscaretakerWeb do
    pipe_through :browser # Use the default browser stack

    get "/", PageController, :index
  end

  if Mix.env == :dev do
    forward "/sent_emails", Bamboo.EmailPreviewPlug
  end

  # Other scopes may use custom stacks.
  # scope "/api", SmileyscaretakerWeb do
  #   pipe_through :api
  # end
end
