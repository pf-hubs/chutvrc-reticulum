defmodule RetWeb.Plugs.PostgrestProxy do
  use Plug.Builder

  plug :call

  @spec call(Plug.Conn.t(), []) :: Plug.Conn.t()
  def call(conn, []) do
    case List.first(conn.path_info) do
      "hubs" ->
        case conn.method() do
          "PATCH" ->
            on_hubs_updated(conn)
          _ -> conn
        end
      _ -> conn
    end
    opts = ReverseProxyPlug.init(upstream: "http://#{hostname()}:3001")
    ReverseProxyPlug.call(conn, opts)
  end

  @spec hostname :: String.t()
  defp hostname,
    do:
      :ret
      |> Application.fetch_env!(__MODULE__)
      |> Keyword.fetch!(:hostname)

  defp on_hubs_updated(conn) do
    case Regex.run(~r/id=eq\.(\d+)/, conn.query_string) do
      nil -> {:error, "No match found"}
      match ->
        RetWeb.HubChannel.refresh_room_by_id(List.last(match))
    end
  end
end

defmodule RetWeb.Plugs.ItaProxy do
  use Plug.Builder
  plug ReverseProxyPlug, upstream: "http://localhost:6000"
end
