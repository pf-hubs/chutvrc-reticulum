defmodule RetWeb.Api.V1.AccountSearchController do
  use RetWeb, :controller

  alias Ret.{Account}
  alias RetWeb.Api.V1.{AccountView}

  # Account lookup, is a POST because lookup contains sensitive information
  def create(conn, %{"email" => email}) do
    with %Account{} = account <- Account.account_for_email(email) do
      record = Phoenix.View.render(AccountView, "show.json", account: account)
      conn |> send_resp(200, %{data: record} |> Poison.encode!())
    else
      _ -> conn |> put_status(:not_found) |> halt()
    end
  end
end
