defmodule Ret.LivekitTokenGenerator do
  @moduledoc """
  Generates LiveKit access tokens for room participants.
  Uses JWT with HS256 signature for LiveKit Cloud authentication.
  """

  require Logger

  @doc """
  Generates an access token for a participant to join a LiveKit room.

  ## Parameters
    - room_name: The name/id of the room to join
    - participant_identity: Unique identifier for the participant
    - opts: Optional keyword list with:
      - can_publish: Whether participant can publish tracks (default: true)
      - can_subscribe: Whether participant can subscribe to tracks (default: true)
      - can_publish_data: Whether participant can send data messages (default: true)

  ## Returns
    - Access token string on success
    - Empty string on failure
  """
  def generate_access_token(room_name, participant_identity, opts \\ []) do
    api_key = get_api_key()
    api_secret = get_api_secret()

    if api_key == "" or api_secret == "" do
      Logger.error("LiveKit API key or secret not configured")
      ""
    else
      can_publish = Keyword.get(opts, :can_publish, true)
      can_subscribe = Keyword.get(opts, :can_subscribe, true)
      can_publish_data = Keyword.get(opts, :can_publish_data, true)

      now = DateTime.utc_now() |> DateTime.to_unix()
      # Token valid for 24 hours
      exp = now + 24 * 60 * 60

      # LiveKit JWT claims structure
      claims = %{
        "iss" => api_key,
        "sub" => participant_identity,
        "iat" => now,
        "nbf" => now,
        "exp" => exp,
        "video" => %{
          "roomJoin" => true,
          "room" => room_name,
          "canPublish" => can_publish,
          "canSubscribe" => can_subscribe,
          "canPublishData" => can_publish_data
        }
      }

      case generate_jwt(claims, api_secret) do
        {:ok, token} ->
          Logger.info("LiveKit token generated for room: #{room_name}, participant: #{participant_identity}")
          token

        {:error, reason} ->
          Logger.error("Failed to generate LiveKit token: #{inspect(reason)}")
          ""
      end
    end
  end

  @doc """
  Returns the configured LiveKit server URL.
  """
  def get_server_url do
    Ret.ServerConfig.get_cached_config_value("webrtc-settings|livekit_server_url") ||
      Application.get_env(:ret, __MODULE__, [])[:server_url] || ""
  end

  @doc """
  Checks if LiveKit is properly configured.
  """
  def configured? do
    get_api_key() != "" and get_api_secret() != "" and get_server_url() != ""
  end

  # Private functions

  defp get_api_key do
    Ret.ServerConfig.get_cached_config_value("webrtc-settings|livekit_api_key") ||
      Application.get_env(:ret, __MODULE__, [])[:api_key] || ""
  end

  defp get_api_secret do
    Ret.ServerConfig.get_cached_config_value("webrtc-settings|livekit_api_secret") ||
      Application.get_env(:ret, __MODULE__, [])[:api_secret] || ""
  end

  defp generate_jwt(claims, secret) do
    try do
      # Create signer with HS256 algorithm
      signer = Joken.Signer.create("HS256", secret)

      # Encode and sign the claims
      case Joken.encode_and_sign(claims, signer) do
        {:ok, token, _claims} -> {:ok, token}
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end
