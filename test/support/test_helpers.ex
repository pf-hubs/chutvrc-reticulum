defmodule Ret.TestHelpers do
  alias Ret.{Storage, Project, Account, Asset, ProjectAsset, Scene, SceneListing, Repo, Hub}

  def generate_temp_owned_file(account) do
    temp_file = generate_temp_file("test")
    {:ok, uuid} = Storage.store(%Plug.Upload{path: temp_file}, "text/plain", "secret")
    {:ok, owned_file} = Storage.promote(uuid, "secret", nil, account)
    owned_file
  end

  def generate_fixture_owned_file(account, path, content_type) do
    {:ok, uuid} = Storage.store(%Plug.Upload{path: path}, content_type, "secret")
    {:ok, owned_file} = Storage.promote(uuid, "secret", nil, account)
    owned_file
  end

  def generate_temp_file(contents) do
    {:ok, temp_path} = Temp.mkdir("stored-file-test")
    file_path = temp_path |> Path.join("test.txt")
    file_path |> File.write(contents)
    file_path
  end

  def create_account() do
    Account.account_for_email("test@mozilla.com")
  end

  def create_account(_) do
    {:ok, account: create_account()}
  end

  def create_owned_file(%{account: account}) do
    {:ok, owned_file: generate_temp_owned_file(account)}
  end

  def create_scene(%{account: account, owned_file: owned_file}) do
    {:ok, scene} =
      %Scene{}
      |> Scene.changeset(account, owned_file, owned_file, owned_file, %{
        name: "Test Scene",
        description: "Test Scene Description",
        allow_promotion: true
      })
      |> Repo.insert_or_update()

    scene = scene |> Repo.preload([:model_owned_file, :screenshot_owned_file, :scene_owned_file, :account])
    {:ok, scene: scene}
  end

  def create_scene_listing(%{scene: scene}) do
    {:ok, listing} =
      %SceneListing{}
      |> SceneListing.changeset_for_listing_for_scene(
        scene,
        %{tags: %{tags: ["foo", "bar", "biz"]}}
      )
      |> Repo.insert()

    {:ok, scene_listing: listing}
  end

  def create_hub(%{scene: scene}) do
    {:ok, hub} = %Hub{} |> Hub.changeset(scene, %{name: "Test Hub"}) |> Repo.insert()

    {:ok, hub: hub}
  end

  def create_project_owned_file(%{account: account}) do
    project_file = Path.expand("../fixtures/spoke-project.json", __DIR__)
    {:ok, project_owned_file: generate_fixture_owned_file(account, project_file, "application/json")}
  end

  def create_thumbnail_owned_file(%{account: account}) do
    thumbnail_file = Path.expand("../fixtures/spoke-thumbnail.jpg", __DIR__)
    {:ok, thumbnail_owned_file: generate_fixture_owned_file(account, thumbnail_file, "image/png")}
  end

  def create_project(%{account: account, project_owned_file: project_owned_file, thumbnail_owned_file: thumbnail_owned_file}) do
    {:ok, project} =
      %Project{}
      |> Project.changeset(account, project_owned_file, thumbnail_owned_file, %{
        name: "Test Scene"
      })
      |> Repo.insert_or_update()

    project = project |> Repo.preload([:project_owned_file, :thumbnail_owned_file, :created_by_account])
    {:ok, project: project}
  end

  def create_project_asset(%{account: account, project: project, thumbnail_owned_file: owned_file}) do
    {:ok, asset} =
      %Asset{}
      |> Asset.changeset(account, owned_file, owned_file, %{
        name: "Test Asset"
      })
      |> Repo.insert_or_update()

    {:ok, project_asset} =
      %ProjectAsset{}
      |> ProjectAsset.changeset(project, asset)
      |> Repo.insert_or_update()

    project_asset = project_asset |> Repo.preload([:project, :asset])
    {:ok, project_asset: project_asset}
  end

  def clear_all_stored_files do
    File.rm_rf(Application.get_env(:ret, Storage)[:storage_path])
  end

  def put_auth_header_for_account(conn, email) do
    {:ok, token, _claims} =
      email
      |> Ret.Account.account_for_email()
      |> Ret.Guardian.encode_and_sign()

    conn |> Plug.Conn.put_req_header("authorization", "bearer: " <> token)
  end
end
