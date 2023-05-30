defmodule RetWeb.Api.V1.ServerConfigController do
  use RetWeb, :controller
  alias Ret.{ServerConfig}

  # def get_schemas(conn, _params) do
  #   conn
  #   |> put_resp_header("content-type", "application/json")
  #   |> send_resp(200, ServerConfig.get_schemas() |> Poison.encode!())
  # end

  def get_admin_info(conn, _params) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, ServerConfig.get_admin_info() |> Poison.encode!())
  end

  def get_editable_config(conn, _params) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, ServerConfig.get_config() |> Poison.encode!())
  end

  def create(conn, server_config_json) do
    # We expect the request body to be a json object where the leaf nodes are the config values.
    account = Guardian.Plug.current_resource(conn)

    server_config_json
    |> ServerConfig.collapse()
    |> Enum.each(fn {key, val} -> ServerConfig.set_config_value(key, val, account) end)

    conn |> send_resp(200, "")
  end

  def index(conn, _params) do
    conn
    |> put_resp_header("content-type", "application/json")
    |> send_resp(200, ServerConfig.get_config() |> Poison.encode!())
  end
end
