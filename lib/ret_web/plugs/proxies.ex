defmodule RetWeb.Plugs.PostgrestProxy do
  use Plug.Builder
  require Logger

  plug :call

  @spec call(Plug.Conn.t(), []) :: Plug.Conn.t()
  def call(conn, []) do
    case conn.method() do
      "PATCH" ->
        on_patch(conn)
      _ ->
        conn
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

  defp on_patch(conn) do
    case Regex.run(~r/id=eq\.(\d+)/, conn.query_string) do
      nil -> {:error, "No match found"}
      match ->
        id = List.last(match)
        case Ret.Hub |> Ret.Repo.get_by(hub_id: id) do
          nil -> {:error, "No record found"}
          hub ->
            RetWeb.Endpoint.broadcast("hub:" <> hub.hub_sid, "hub_refresh_by_admin", %{})
        end
    end
  end
end

defmodule RetWeb.Plugs.ItaProxy do
  use Plug.Builder
  plug ReverseProxyPlug, upstream: "http://localhost:6000"
end
