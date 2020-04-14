defmodule Ret.Coturn do
  # Adds a new secret, and removes secrets older than an hour
  # Note this is safe to run on a multi-node cluster since coturn respects all secrets in the db.
  def rotate_secrets do
    if enabled?() do
      Ecto.Adapters.SQL.query!(
        Ret.Repo,
        "INSERT INTO coturn.turn_secret (realm, value, inserted_at, updated_at) values ($1, $2, now(), now())",
        [realm(), SecureRandom.hex()]
      )

      Ecto.Adapters.SQL.query!(
        Ret.Repo,
        "DELETE FROM coturn.turn_secret WHERE inserted_at < now() - interval '1 day'"
      )
    end
  end

  def generate_credentials do
    {_, coturn_secret} = Cachex.fetch(:coturn_secret, :coturn_secret)

    # Credentials are good for two minutes, since we connect immediately.
    username = "#{Timex.now() |> Timex.shift(minutes: 2) |> Timex.to_unix()}:hubs"
    credential = :crypto.hmac(:sha, coturn_secret, username) |> :base64.encode()

    {username, credential}
  end

  def latest_secret_commit(_key) do
    if enabled?() do
      %Postgrex.Result{rows: [[secret]]} =
        Ecto.Adapters.SQL.query!(
          Ret.Repo,
          "SELECT value FROM coturn.turn_secret WHERE realm = $1 ORDER BY inserted_at DESC LIMIT 1",
          [realm()]
        )

      {:commit, secret}
    else
      {:commit, nil}
    end
  end

  def enabled? do
    !!realm()
  end

  defp realm do
    Application.get_env(:ret, __MODULE__)[:realm]
  end
end
