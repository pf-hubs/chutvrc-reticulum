defmodule RetWeb.Api.V1.MediaController do
  use RetWeb, :controller
  use Retry

  def create(conn, %{"media" => %{"url" => url}}) do
    resolve_and_render(conn, url)
  end

  def create(
        conn,
        %{"media" => %Plug.Upload{filename: filename, content_type: "application/octet-stream"} = upload} = params
      ) do
    desired_content_type = params |> Map.get("desired_content_type")
    promotion_token = params |> promotion_token_for_params

    store_and_render_upload(conn, upload, MIME.from_path(filename), desired_content_type, promotion_token)
  end

  def create(conn, %{"media" => %Plug.Upload{content_type: content_type} = upload} = params) do
    desired_content_type = params |> Map.get("desired_content_type")
    promotion_token = params |> promotion_token_for_params

    store_and_render_upload(conn, upload, content_type, desired_content_type, promotion_token)
  end

  defp promotion_token_for_params(%{"promotion_mode" => "with_token"}), do: SecureRandom.hex()
  defp promotion_token_for_params(_params), do: nil

  defp store_and_render_upload(conn, upload, content_type, nil = _desired_content_type, promotion_token) do
    store_and_render_upload(conn, upload, content_type, promotion_token)
  end

  defp store_and_render_upload(conn, upload, content_type, desired_content_type, promotion_token) do
    case Ret.Speelycaptor.convert(upload, desired_content_type) do
      {:ok, converted_path} ->
        converted_upload = %Plug.Upload{
          path: converted_path,
          filename: upload.filename,
          content_type: desired_content_type
        }

        store_and_render_upload(conn, converted_upload, desired_content_type, promotion_token)

      _ ->
        store_and_render_upload(conn, upload, desired_content_type || content_type, promotion_token)
    end
  end

  defp store_and_render_upload(conn, upload, content_type, promotion_token) do
    access_token = SecureRandom.hex()

    case Ret.Storage.store(upload, content_type, access_token, promotion_token) do
      {:ok, uuid} ->
        uri = Ret.Storage.uri_for(uuid, content_type)

        conn
        |> render(
          "show.json",
          file_id: uuid,
          origin: uri |> URI.to_string(),
          raw: uri |> URI.to_string(),
          meta: %{access_token: access_token, promotion_token: promotion_token, expected_content_type: content_type}
        )

      {:error, :quota} ->
        conn |> send_resp(400, "Unable to store additional content.")

      {:error, :not_allowed} ->
        conn |> send_resp(401, "")
    end
  end

  defp resolve_and_render(conn, url) do
    ua =
      conn
      |> Plug.Conn.get_req_header("user-agent")
      |> List.first()
      |> UAParser.parse()

    supports_webm = ua.family != "Safari" && ua.family != "Mobile Safari"
    low_resolution = ua.os.family == "Android" || ua.os.family == "iOS"

    case Cachex.fetch(:media_urls, %Ret.MediaResolverQuery{
           url: url,
           supports_webm: supports_webm,
           low_resolution: low_resolution
         }) do
      {_status, nil} ->
        conn |> send_resp(404, "")

      {_status, %Ret.ResolvedMedia{} = resolved_media} ->
        render_resolved_media(conn, resolved_media)

      _ ->
        conn |> send_resp(404, "")
    end
  end

  defp render_resolved_media(conn, %Ret.ResolvedMedia{uri: uri, meta: meta}) do
    conn |> render("show.json", origin: uri |> URI.to_string(), meta: meta)
  end
end
