defmodule RetWeb.Api.V1.HubController do
  use RetWeb, :controller

  alias Ret.{Hub, Scene, SceneListing, Repo}

  import Canada, only: [can?: 2]

  # Limit to 1 TPS
  plug(RetWeb.Plugs.RateLimit)

  # Only allow access to remove hubs with secret header
  plug(RetWeb.Plugs.HeaderAuthorization when action in [:delete])

  def create(conn, %{"hub" => %{"scene_id" => scene_id}} = params) do
    scene = Scene.scene_or_scene_listing_by_sid(scene_id)

    %Hub{}
    |> Hub.changeset(scene, params["hub"])
    |> exec_create(conn)
  end

  def create(conn, %{"hub" => _hub_params} = params) do
    scene_listing = SceneListing.get_random_default_scene_listing()

    %Hub{}
    |> Hub.changeset(scene_listing, params["hub"])
    |> exec_create(conn)
  end

  defp exec_create(hub_changeset, conn) do
    account = Guardian.Plug.current_resource(conn)

    if account |> can?(create_hub(nil)) do
      {result, hub} =
        hub_changeset
        |> Hub.add_account_to_changeset(account)
        |> Repo.insert()

      case result do
        :ok -> render(conn, "create.json", hub: hub)
        :error -> conn |> send_resp(422, "invalid hub")
      end
    else
      conn |> send_resp(401, "unauthorized")
    end
  end

  def update(conn, %{"id" => hub_sid, "hub" => hub_params}) do
    account = Guardian.Plug.current_resource(conn)

    case Hub |> Repo.get_by(hub_sid: hub_sid) |> Repo.preload([:created_by_account, :hub_bindings, :hub_role_memberships]) do
      %Hub{} = hub -> 
        if account |> can?(update_hub(hub)) do
          update_with_hub(conn, account, hub, hub_params)
        else
          conn |> send_resp(401, "You cannot update this hub")
        end
      _ -> conn |> send_resp(404, "not found")
    end
  end

  defp update_with_hub(conn, account, hub, hub_params) do
    if is_nil(hub_params["scene_id"]) do
      update_with_hub_and_scene(conn, account, hub, nil, hub_params)
    else
      case Scene.scene_or_scene_listing_by_sid(hub_params["scene_id"]) do
        nil -> conn |> send_resp(422, "scene not found")
        scene -> update_with_hub_and_scene(conn, account, hub, scene, hub_params)
      end
    end
  end

  defp update_with_hub_and_scene(conn, account, hub, scene, hub_params) do
    changeset = hub |> Hub.add_attrs_to_changeset(hub_params)
    
    if not is_nil(scene) do
      changeset |> Hub.changeset_for_new_scene(scene)
    end

    if not is_nil(hub_params["member_permissions"]) do
      changeset |> Hub.add_member_permissions_to_changeset(hub_params)
    end

    if not is_nil(hub_params["allow_promotion"]) do
      changeset |> Hub.maybe_add_promotion_to_changeset(account, hub, hub_params)
    end

    hub = changeset |> Repo.update!() |> Repo.preload(Hub.hub_preloads())

    conn |> render("show.json", %{ hub: hub, embeddable: account |> can?(embed_hub(hub))})
  end


  def delete(conn, %{"id" => hub_sid}) do
    Hub
    |> Repo.get_by(hub_sid: hub_sid)
    |> Hub.changeset_for_entry_mode(:deny)
    |> Repo.update!()

    conn |> send_resp(200, "OK")
  end
end
