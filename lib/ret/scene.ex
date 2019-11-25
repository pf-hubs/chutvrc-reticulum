defmodule Ret.Scene.SceneSlug do
  use EctoAutoslugField.Slug, from: :name, to: :slug, always_change: true

  def get_sources(_changeset, _opts) do
    [:scene_sid, :name]
  end
end

defmodule Ret.Scene do
  use Ecto.Schema
  import Ecto.Changeset

  alias Ret.{Repo, Scene, SceneListing, Project, Storage}
  alias Ret.Scene.{SceneSlug}

  @schema_prefix "ret0"
  @primary_key {:scene_id, :id, autogenerate: true}

  schema "scenes" do
    field(:scene_sid, :string)
    field(:slug, SceneSlug.Type)
    field(:name, :string)
    field(:description, :string)
    field(:attribution, :string)
    field(:attributions, :map)
    field(:allow_remixing, :boolean)
    field(:allow_promotion, :boolean)

    field(:imported_from_host, :string)
    field(:imported_from_port, :integer)
    field(:imported_from_sid, :string)

    belongs_to(:parent_scene, Scene, references: :scene_id, on_replace: :nilify)
    belongs_to(:parent_scene_listing, SceneListing, references: :scene_listing_id, on_replace: :nilify)
    has_one(:project, Project, foreign_key: :scene_id)

    belongs_to(:account, Ret.Account, references: :account_id)
    belongs_to(:model_owned_file, Ret.OwnedFile, references: :owned_file_id, on_replace: :nilify)
    belongs_to(:screenshot_owned_file, Ret.OwnedFile, references: :owned_file_id, on_replace: :nilify)
    belongs_to(:scene_owned_file, Ret.OwnedFile, references: :owned_file_id, on_replace: :nilify)
    field(:state, Scene.State)

    timestamps()
  end

  def scene_or_scene_listing_by_sid(sid) do
    Scene |> Repo.get_by(scene_sid: sid) || SceneListing |> Repo.get_by(scene_listing_sid: sid) |> Repo.preload(:scene)
  end

  def to_sid(nil), do: nil
  def to_sid(%Scene{} = scene), do: scene.scene_sid
  def to_sid(%SceneListing{} = scene_listing), do: scene_listing.scene_listing_sid
  def to_url(%t{} = s) when t in [Scene, SceneListing], do: "#{RetWeb.Endpoint.url()}/scenes/#{s |> to_sid}/#{s.slug}"

  defp fetch_remote_scene!(uri) do
    %{body: body} = HTTPoison.get!(uri)
    body |> Poison.decode!() |> get_in(["scenes", Access.at(0)])
  end

  def new_scene_from_parent_scene(parent_scene, account) do
    {:ok, model_owned_file} = Storage.duplicate(parent_scene.model_owned_file, account)
    {:ok, screenshot_owned_file} = Storage.duplicate(parent_scene.screenshot_owned_file, account)
    {:ok, scene_owned_file} = Storage.duplicate(parent_scene.scene_owned_file, account)

    {:ok, new_scene} =
      Repo.transaction(fn ->
        new_scene =
          %Scene{}
          |> Scene.changeset(
            account,
            model_owned_file,
            screenshot_owned_file,
            scene_owned_file,
            parent_scene,
            %{
              name: parent_scene.name,
              description: parent_scene.description,
              attributions: parent_scene.attributions,
              allow_remixing: parent_scene.allow_remixing,
              allow_promotion: parent_scene.allow_promotion
            }
          )
          |> Repo.insert!()

        %Project{}
        |> Project.changeset(account, scene_owned_file, screenshot_owned_file, %{name: new_scene.name})
        |> put_assoc(:scene, new_scene)
        |> Repo.insert!()

        new_scene
      end)

    new_scene
  end

  def import_from_url!(uri, account) do
    remote_scene = uri |> fetch_remote_scene!()
    [imported_from_host, imported_from_port] = [:host, :port] |> Enum.map(&(uri |> URI.parse() |> Map.get(&1)))
    imported_from_sid = remote_scene["scene_id"]

    [model_owned_file, screenshot_owned_file] =
      [remote_scene["model_url"], remote_scene["screenshot_url"]] |> Storage.owned_files_from_urls!(account)

    scene_owned_file =
      if remote_scene["scene_project_url"] do
        [remote_scene["scene_project_url"]] |> Storage.owned_files_from_urls!(account) |> Enum.at(0)
      else
        nil
      end

    scene =
      Scene
      |> Repo.get_by(
        imported_from_host: imported_from_host,
        imported_from_port: imported_from_port,
        imported_from_sid: imported_from_sid
      )
      |> Repo.preload([
        :account,
        :model_owned_file,
        :screenshot_owned_file,
        :scene_owned_file,
        :parent_scene,
        :parent_scene_listing
      ])

    # Disallow non-admins from importing if account varies
    if scene && scene.account_id != account.account_id && !account.is_admin do
      raise "Cannot import existing scene, owned by another account."
    end

    {:ok, new_scene} =
      (scene || %Scene{})
      |> Scene.changeset(account, model_owned_file, screenshot_owned_file, scene_owned_file, %{
        name: remote_scene["name"],
        description: remote_scene["description"],
        attributions: remote_scene["attributions"],
        allow_remixing: remote_scene["allow_remixing"],
        imported_from_host: imported_from_host,
        imported_from_port: imported_from_port,
        imported_from_sid: imported_from_sid,
        allow_promotion: true
      })
      |> Repo.insert_or_update()

    new_scene
  end

  def changeset(
        %Scene{} = scene,
        account,
        model_owned_file,
        screenshot_owned_file,
        scene_owned_file,
        params \\ %{}
      ) do
    scene
    |> cast(params, [
      :name,
      :description,
      :attribution,
      :attributions,
      :allow_remixing,
      :allow_promotion,
      :imported_from_host,
      :imported_from_port,
      :imported_from_sid,
      :state
    ])
    |> validate_required([
      :name
    ])
    |> validate_length(:name, min: 4, max: 64)
    # TODO BP: this is repeated from hub.ex. Maybe refactor the regex out.
    |> validate_format(:name, ~r/^[A-Za-z0-9-':"!@#$%^&*(),.?~ ]+$/)
    |> maybe_add_scene_sid_to_changeset
    |> unique_constraint(:scene_sid)
    |> put_assoc(:account, account)
    |> put_assoc(:model_owned_file, model_owned_file)
    |> put_assoc(:screenshot_owned_file, screenshot_owned_file)
    |> put_assoc(:scene_owned_file, scene_owned_file)
    |> SceneSlug.maybe_generate_slug()
  end

  def changeset(
        %Scene{} = scene,
        account,
        model_owned_file,
        screenshot_owned_file,
        scene_owned_file,
        nil = _parent_scene,
        params
      ) do
    changeset(scene, account, model_owned_file, screenshot_owned_file, scene_owned_file, params)
  end

  def changeset(
        %Scene{} = scene,
        account,
        model_owned_file,
        screenshot_owned_file,
        scene_owned_file,
        %Scene{} = parent_scene,
        params
      ) do
    changeset(scene, account, model_owned_file, screenshot_owned_file, scene_owned_file, params)
    |> put_assoc(:parent_scene, parent_scene)
  end

  def changeset(
        %Scene{} = scene,
        account,
        model_owned_file,
        screenshot_owned_file,
        scene_owned_file,
        %SceneListing{} = parent_scene_listing,
        params
      ) do
    changeset(scene, account, model_owned_file, screenshot_owned_file, scene_owned_file, params)
    |> put_assoc(:parent_scene_listing, parent_scene_listing)
  end

  def changeset_to_mark_as_reviewed(%Scene{} = scene) do
    scene
    |> Ecto.Changeset.change()
    |> put_change(:reviewed_at, Timex.now() |> DateTime.truncate(:second))
  end

  defp maybe_add_scene_sid_to_changeset(changeset) do
    scene_sid = changeset |> get_field(:scene_sid) || Ret.Sids.generate_sid()
    put_change(changeset, :scene_sid, scene_sid)
  end
end
