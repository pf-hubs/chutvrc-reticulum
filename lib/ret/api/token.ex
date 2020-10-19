defmodule Ret.Api.Token do
  @moduledoc """
  ApiTokens determine what actions are allowed to be taken via the public API.
  """
  use Guardian, otp_app: :ret, secret_fetcher: Ret.ApiTokenSecretFetcher

  import Ecto.Query

  alias Ret.{Account, Repo}
  alias Ret.Api.Scopes

  @app_token_string "reticulum_app_token"

  def subject_for_token(%Account{} = account, _), do: {:ok, to_string(account.account_id)}
  def subject_for_token(:reticulum_app_token, _), do: {:ok, @app_token_string}
  def subject_for_token(_, _), do: {:error, "Must pass account or #{@app_token_string}"}

  def resource_from_claims(%{"sub" => nil}) do
    {:error, "No subject in token"}
  end

  def resource_from_claims(%{"sub" => @app_token_string}) do
    {:ok, :reticulum_app_token}
  end

  def resource_from_claims(%{"sub" => account_id}) do
    result_for_account(Repo.one(where(Account, [a], a.account_id == ^account_id)))
  end

  defp result_for_account(%Account{} = account), do: {:ok, account}
  defp result_for_account(nil), do: {:error, "Account not found"}

  def after_encode_and_sign(resource, claims, token, _options) do
    with {:ok, _} <- Guardian.DB.after_encode_and_sign(resource, claims["typ"], claims, token) do
      {:ok, token}
    end
  end

  def on_verify(claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_verify(claims, token) do
      {:ok, claims}
    end
  end

  def on_refresh({old_token, old_claims}, {new_token, new_claims}, _options) do
    with {:ok, _, _} <- Guardian.DB.on_refresh({old_token, old_claims}, {new_token, new_claims}) do
      {:ok, {old_token, old_claims}, {new_token, new_claims}}
    end
  end

  def on_revoke(claims, token, _options) do
    with {:ok, _} <- Guardian.DB.on_revoke(claims, token) do
      {:ok, claims}
    end
  end
end
