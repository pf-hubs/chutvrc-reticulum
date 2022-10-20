defmodule RetWeb.ApiInternal.V1.ChangeLoginEmailControllerTest do
  use RetWeb.ConnCase
  import Ret.TestHelpers
  alias Ret.Account

  @dashboard_access_header "x-ret-dashboard-access-key"
  @dashboard_access_key "test-key"

  setup_all do
    merge_module_config(:ret, RetWeb.Plugs.DashboardHeaderAuthorization, %{dashboard_access_key: @dashboard_access_key})

    on_exit(fn ->
      Ret.TestHelpers.merge_module_config(:ret, RetWeb.Plugs.DashboardHeaderAuthorization, %{dashboard_access_key: nil})
    end)
  end

  test "new email addresses must be valid", %{conn: conn} do
    Account.find_or_create_account_for_email("alice@reticulum.io")
    assert Account.exists_for_email?("alice@reticulum.io")
    assert %{status: 400} = post_change_email_for_login(conn, "not_an_email_address", "alice@reticulum.io")
    refute Account.exists_for_email?("not_an_email_address")
    assert Account.exists_for_email?("alice@reticulum.io")
  end

  test "email addresses validation only applies to new emails", %{conn: conn} do
    Account.find_or_create_account_for_email("not_an_email_address")
    assert Account.exists_for_email?("not_an_email_address")
    assert %{status: 200} = post_change_email_for_login(conn, "alice@reticulum.io", "not_an_email_address")
    assert Account.exists_for_email?("alice@reticulum.io")
    refute Account.exists_for_email?("not_an_email_address")
  end

  test "account emails can be changed", %{conn: conn} do
    refute Account.exists_for_email?("alice@reticulum.io")
    Account.find_or_create_account_for_email("alice@reticulum.io")
    assert Account.exists_for_email?("alice@reticulum.io")
    refute Account.exists_for_email?("alicia@anotherdomain.com")
    assert %{status: 200} = post_change_email_for_login(conn, "alicia@anotherdomain.com", "alice@reticulum.io")
    refute Account.exists_for_email?("alice@reticulum.io")
    assert Account.exists_for_email?("alicia@anotherdomain.com")
  end

  test "emails cannot be shared between multiple accounts", %{conn: conn} do
    Account.find_or_create_account_for_email("alice@reticulum.io")
    Account.find_or_create_account_for_email("bob@reticulum.io")
    assert %{status: 409} = post_change_email_for_login(conn, "bob@reticulum.io", "alice@reticulum.io")
  end

  test "email changes are rejected if old_email is not associated with an account", %{conn: conn} do
    assert %{status: 409} = post_change_email_for_login(conn, "bob@reticulum.io", "alice@reticulum.io")
    Account.find_or_create_account_for_email("bob@reticulum.io")
    assert %{status: 409} = post_change_email_for_login(conn, "bob@reticulum.io", "alice@reticulum.io")
  end

  test "email changes must be authenticated", %{conn: conn} do
    Account.find_or_create_account_for_email("alice@reticulum.io")

    assert %{status: 401} =
             conn
             |> post("/api-internal/v1/change_email_for_login", %{
               "old_email" => "alice@reticulum.io",
               "new_email" => "bob@reticulum.io"
             })

    assert Account.exists_for_email?("alice@reticulum.io")
    refute Account.exists_for_email?("bob@reticulum.io")
  end

  defp post_change_email_for_login(conn, new_email, old_email) do
    conn
    |> put_req_header(@dashboard_access_header, @dashboard_access_key)
    |> post("/api-internal/v1/change_email_for_login", %{"old_email" => old_email, "new_email" => new_email})
  end
end
