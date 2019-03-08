defmodule RetWeb.Plugs.BotHeaderAuthorization do
  import Plug.Conn
  @header_name "x-ret-bot-access-key"

  def init(default), do: default

  def call(conn, _default) do
    env = Application.get_env(:ret, __MODULE__)
    expected_value = env[:bot_access_key]

    case conn |> get_req_header(@header_name) do
      [^expected_value] -> conn
      _ -> conn |> send_resp(401, "") |> halt()
    end
  end
end
