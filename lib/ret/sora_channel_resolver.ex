defmodule Ret.SoraChannelResolver do
  require Logger
  require HTTPoison

  @api_endpoint "https://api.sora-cloud.shiguredo.app/projects/create-access-token"
  @bearer_token "xxx"
  @project_id "xxx"

  def request_access_token(channel_id) do
    headers = [
      {"Authorization", "Bearer #{@bearer_token}"},
      {"Content-Type", "application/json"}
    ]

    body = Poison.encode!(%{
      channel_id: "#{channel_id}@#{@project_id}",
      not_before: DateTime.utc_now() |> Timex.format("%FT%T%:z", :strftime) |> elem(1),
      expiration_time: DateTime.utc_now() |> Timex.shift(months: 1) |> Timex.format("%FT%T%:z", :strftime) |> elem(1)
    })

    case HTTPoison.post(@api_endpoint, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        access_token = Poison.decode(body) |> elem(1) |> Map.get("access_token")
        Logger.info("POST request successful: #{inspect(access_token)}")
        access_token

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("POST request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
