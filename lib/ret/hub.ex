defmodule Ret.Hub.HubSlug do
  use EctoAutoslugField.Slug, from: :name, to: :slug, always_change: true

  def get_sources(_changeset, _opts) do
    [:hub_sid, :name]
  end
end

defmodule Ret.Hub do
  use Ecto.Schema
  use Bitwise

  import Ecto.Changeset
  import Ecto.Query
  import Canada, only: [can?: 2]

  alias Ret.{
    Account,
    Hub,
    Repo,
    Scene,
    SceneListing,
    WebPushSubscription,
    RoomAssigner,
    BitFieldUtils,
    HubRoleMembership
  }

  alias Ret.Hub.{HubSlug}

  @schema_prefix "ret0"
  @primary_key {:hub_id, :id, autogenerate: true}
  @max_entry_code 999_999
  @entry_code_expiration_hours 72
  @max_entry_code_generate_attempts 25

  @member_permissions %{
    (1 <<< 0) => :spawn_and_move_media,
    (1 <<< 1) => :spawn_camera,
    (1 <<< 2) => :spawn_drawing,
    (1 <<< 3) => :pin_objects
  }

  @member_permissions_keys @member_permissions |> Map.values()

  @default_member_permissions %{
    spawn_and_move_media: true,
    spawn_camera: true,
    spawn_drawing: true,
    pin_objects: true
  }

  @default_restrictive_member_permissions %{
    spawn_and_move_media: false,
    spawn_camera: false,
    spawn_drawing: false,
    pin_objects: false
  }

  schema "hubs" do
    field(:name, :string)
    field(:hub_sid, :string)
    field(:host, :string)
    field(:entry_code, :integer)
    field(:entry_code_expires_at, :utc_datetime)
    field(:last_active_at, :utc_datetime)
    field(:creator_assignment_token, :string)
    field(:embed_token, :string)
    field(:embedded, :boolean)
    field(:member_permissions, :integer)
    field(:default_environment_gltf_bundle_url, :string)
    field(:slug, HubSlug.Type)
    field(:max_occupant_count, :integer, default: 0)
    field(:spawned_object_types, :integer, default: 0)
    field(:entry_mode, Ret.Hub.EntryMode)
    belongs_to(:scene, Ret.Scene, references: :scene_id)
    belongs_to(:scene_listing, Ret.SceneListing, references: :scene_listing_id)
    has_many(:web_push_subscriptions, Ret.WebPushSubscription, foreign_key: :hub_id)
    belongs_to(:created_by_account, Ret.Account, references: :account_id)
    has_many(:hub_bindings, Ret.HubBinding, foreign_key: :hub_id)
    has_many(:hub_role_memberships, Ret.HubRoleMembership, foreign_key: :hub_id)

    field(:privacy, Hub.Privacy)

    timestamps()
  end

  def get_by_entry_code_string(entry_code_string) when is_binary(entry_code_string) do
    case Integer.parse(entry_code_string) do
      {entry_code, _} -> Hub |> Repo.get_by(entry_code: entry_code)
      _ -> nil
    end
  end

  def changeset(%Hub{} = hub, %Scene{} = scene, attrs) do
    hub
    |> changeset(nil, attrs)
    |> put_assoc(:scene, scene)
  end

  def changeset(%Hub{} = hub, %SceneListing{} = scene_listing, attrs) do
    hub
    |> changeset(nil, attrs)
    |> put_assoc(:scene_listing, scene_listing)
  end

  def changeset(%Hub{} = hub, nil, attrs) do
    hub
    |> cast(attrs, [:default_environment_gltf_bundle_url])
    |> add_name_to_changeset(attrs)
    |> add_hub_sid_to_changeset
    |> add_generated_tokens_to_changeset
    |> add_entry_code_to_changeset
    |> add_default_member_permissions_to_changeset
    |> unique_constraint(:hub_sid)
    |> unique_constraint(:entry_code)
  end

  def add_name_to_changeset(changeset, attrs) do
    changeset
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 64)
    |> HubSlug.maybe_generate_slug()
  end

  def member_permissions_from_attrs(%{} = attrs) do
    attrs["member_permissions"] |> Map.new(fn {k, v} -> {String.to_atom(k), v} end) |> member_permissions_to_int
  end

  def add_member_permissions_to_changeset(changeset, attrs) do
    member_permissions = attrs |> member_permissions_from_attrs

    changeset
    |> put_change(:member_permissions, member_permissions)
  end

  def add_privacy_to_changeset(changeset, attrs) do
    changeset |> put_change(:privacy, attrs["privacy"])
  end

  def changeset_for_new_seen_occupant_count(%Hub{} = hub, occupant_count) do
    new_max_occupant_count = max(hub.max_occupant_count, occupant_count)

    hub
    |> cast(%{max_occupant_count: new_max_occupant_count}, [:max_occupant_count])
    |> maybe_add_last_active_at_to_changeset(occupant_count)
    |> validate_required([:max_occupant_count])
  end

  def changeset_for_seen_embedded_hub(%Hub{} = hub), do: hub |> cast(%{embedded: true}, [:embedded])

  # NOTE occupant_count is 1 when there is 1 *other* user in the room with you, so active is when >= 1.
  defp maybe_add_last_active_at_to_changeset(changeset, occupant_count) when occupant_count >= 1,
    do: changeset |> put_change(:last_active_at, Timex.now() |> DateTime.truncate(:second))

  defp maybe_add_last_active_at_to_changeset(changeset, _), do: changeset

  def changeset_for_new_scene(%Hub{} = hub, %Scene{} = scene) do
    hub
    |> change()
    |> put_change(:scene_id, scene.scene_id)
    |> put_change(:scene_listing_id, nil)
  end

  def changeset_for_new_scene(%Hub{} = hub, %SceneListing{} = scene_listing) do
    hub
    |> change()
    |> put_change(:scene_listing_id, scene_listing.scene_listing_id)
    |> put_change(:scene_id, nil)
  end

  def changeset_for_new_environment_url(%Hub{} = hub, url) do
    hub
    |> cast(%{default_environment_gltf_bundle_url: url}, [:default_environment_gltf_bundle_url])
    |> validate_required([:default_environment_gltf_bundle_url])
    |> put_change(:scene_id, nil)
    |> put_change(:scene_listing_id, nil)
  end

  def changeset_for_new_spawned_object_type(%Hub{} = hub, object_type)
      when object_type in 0..31 do
    # spawned_object_types is a bitmask of the seen object types
    new_spawned_object_types = hub.spawned_object_types ||| 1 <<< object_type

    hub
    |> cast(%{spawned_object_types: new_spawned_object_types}, [:spawned_object_types])
    |> validate_required([:spawned_object_types])
  end

  def changeset_for_entry_mode(%Hub{} = hub, entry_mode),
    do: hub |> cast(%{entry_mode: entry_mode}, [:entry_mode])

  def changeset_for_new_host(%Hub{} = hub, host), do: hub |> cast(%{host: host}, [:host])

  def changeset_for_creator_assignment(
        %Ret.Hub{creator_assignment_token: expected_token} = hub,
        account,
        token
      )
      when expected_token != nil and expected_token == token do
    hub |> change() |> add_account_to_changeset(account)
  end

  def changeset_for_creator_assignment(hub, _, _), do: hub |> change()

  def add_account_to_changeset(changeset, nil), do: changeset

  def add_account_to_changeset(changeset, %Account{} = account) do
    changeset |> put_assoc(:created_by_account, account) |> put_change(:creator_assignment_token, nil)
  end

  def send_push_messages_for_join(%Hub{web_push_subscriptions: subscriptions} = hub, endpoint_to_skip \\ nil) do
    body = hub |> push_message_for_join

    for subscription <- subscriptions |> Enum.filter(&(&1.endpoint != endpoint_to_skip)) do
      subscription |> WebPushSubscription.maybe_send(body)
    end
  end

  defp push_message_for_join(%Hub{} = hub) do
    %{type: "join", hub_name: hub.name, hub_id: hub.hub_sid, hub_url: hub |> url_for, image: hub |> image_url_for}
    |> Poison.encode!()
  end

  def url_for(%Hub{} = hub) do
    "#{RetWeb.Endpoint.url()}/#{hub.hub_sid}/#{hub.slug}"
  end

  def image_url_for(%Hub{scene: nil, scene_listing: nil}) do
    "#{RetWeb.Endpoint.url()}/app-thumbnail.png"
  end

  def image_url_for(%Hub{scene: scene}) when scene != nil do
    scene.screenshot_owned_file |> Ret.OwnedFile.uri_for() |> URI.to_string()
  end

  def image_url_for(%Hub{scene_listing: scene_listing}) when scene_listing != nil do
    scene_listing.screenshot_owned_file |> Ret.OwnedFile.uri_for() |> URI.to_string()
  end

  def participant_count_for(%Hub{hub_sid: hub_sid}) do
    RetWeb.Presence.list("hub:#{hub_sid}") |> Enum.count()
  end

  defp changeset_for_new_entry_code(%Hub{} = hub) do
    hub
    |> Ecto.Changeset.change()
    |> add_entry_code_to_changeset
  end

  def ensure_valid_entry_code!(hub) do
    if hub |> entry_code_expired? do
      hub |> changeset_for_new_entry_code |> Repo.update!()
    else
      hub
    end
  end

  def ensure_host(hub) do
    if RoomAssigner.is_alive?(hub.host) do
      hub
    else
      # TODO the database mutation should be centralized into the GenServer
      # to ensure a partition doesn't cause a rogue node to re-assign the server
      host = RoomAssigner.get_available_host(hub.host)

      if host && host != hub.host do
        hub |> changeset_for_new_host(host) |> Repo.update!()
      else
        hub
      end
    end
  end

  def entry_code_expired?(%Hub{entry_code: entry_code, entry_code_expires_at: entry_code_expires_at})
      when is_nil(entry_code) or is_nil(entry_code_expires_at),
      do: true

  def entry_code_expired?(%Hub{} = hub) do
    Timex.now() |> Timex.after?(hub.entry_code_expires_at)
  end

  def vacuum_entry_codes do
    Ret.Locking.exec_if_lockable(:hub_vacuum_entry_codes, fn ->
      query = from(h in Hub, where: h.entry_code_expires_at() < ^Timex.now())
      Repo.update_all(query, set: [entry_code: nil, entry_code_expires_at: nil])
    end)
  end

  # Remove the host entry from any rooms that are older than a day old and have no presence
  def vacuum_hosts do
    Ret.Locking.exec_if_lockable(:hub_vacuum_hosts, fn ->
      one_day_ago = Timex.now() |> Timex.shift(days: -1)

      candidate_hub_sids =
        from(h in Hub, where: not is_nil(h.host) and h.inserted_at < ^one_day_ago)
        |> Repo.all()
        |> Enum.map(& &1.hub_sid)

      present_hub_sids = RetWeb.Presence.present_hub_sids()
      clearable_hub_sids = candidate_hub_sids |> Enum.filter(&(!Enum.member?(present_hub_sids, &1)))

      from(h in Hub, where: h.hub_sid in ^clearable_hub_sids) |> Repo.update_all(set: [host: nil])
    end)
  end

  defp add_hub_sid_to_changeset(changeset) do
    hub_sid = Ret.Sids.generate_sid()
    changeset |> put_change(:hub_sid, hub_sid)
  end

  defp add_generated_tokens_to_changeset(changeset) do
    creator_assignment_token = SecureRandom.hex()
    embed_token = SecureRandom.hex()

    changeset
    |> put_change(:creator_assignment_token, creator_assignment_token)
    |> put_change(:embed_token, embed_token)
  end

  defp add_entry_code_to_changeset(changeset) do
    expires_at = Timex.now() |> Timex.shift(hours: @entry_code_expiration_hours) |> DateTime.truncate(:second)

    changeset
    |> put_change(:entry_code, generate_entry_code!())
    |> put_change(:entry_code_expires_at, expires_at)
  end

  defp generate_entry_code!(attempt \\ 0)

  defp generate_entry_code!(attempt) when attempt > @max_entry_code_generate_attempts do
    raise "Unable to allocate entry code"
  end

  defp generate_entry_code!(attempt) do
    candidate_entry_code = :rand.uniform(@max_entry_code)

    case Hub |> Repo.get_by(entry_code: candidate_entry_code) do
      nil -> candidate_entry_code
      _ -> generate_entry_code!(attempt + 1)
    end
  end

  def janus_room_id_for_hub(hub) do
    # Cap to 53 bits of entropy because of Javascript :/
    with <<room_id::size(53), _::size(11), _::binary>> <- :crypto.hash(:sha256, hub.hub_sid) do
      room_id
    end
  end

  defp add_default_member_permissions_to_changeset(changeset) do
    if Ret.AppConfig.get_config_bool("features|permissive_rooms") do
      changeset |> put_change(:member_permissions, @default_member_permissions |> member_permissions_to_int)
    else
      changeset |> put_change(:member_permissions, @default_restrictive_member_permissions |> member_permissions_to_int)
    end
  end

  def add_owner!(%Hub{created_by_account_id: created_by_account_id} = hub, %Account{account_id: account_id})
      when created_by_account_id != nil and created_by_account_id === account_id,
      do: hub

  def add_owner!(%Hub{} = hub, %Account{} = account) do
    Repo.get_by(HubRoleMembership, hub_id: hub.hub_id, account_id: account.account_id) ||
      %HubRoleMembership{} |> HubRoleMembership.changeset(hub, account) |> Repo.insert!()

    hub |> Repo.preload([hub_role_memberships: []], force: true)
  end

  def remove_owner!(%Hub{} = hub, %Account{} = account) do
    case Repo.get_by(HubRoleMembership, hub_id: hub.hub_id, account_id: account.account_id) do
      %HubRoleMembership{} = membership ->
        membership |> Repo.delete!()

      _ ->
        nil
    end

    hub |> Repo.preload([hub_role_memberships: []], force: true)
  end

  def is_creator?(%Hub{created_by_account_id: created_by_account_id}, account_id)
      when created_by_account_id != nil and created_by_account_id === account_id,
      do: true

  def is_creator?(_hub, _account), do: false

  def is_owner?(%Hub{hub_role_memberships: hub_role_memberships} = hub, account_id) do
    is_creator?(hub, account_id) || hub_role_memberships |> Enum.any?(&(&1.account_id === account_id))
  end

  def member_permissions_to_int(%{} = member_permissions) do
    invalid_member_permissions = member_permissions |> Map.drop(@member_permissions_keys) |> Map.keys()

    if invalid_member_permissions |> Enum.count() > 0 do
      raise ArgumentError, "Invalid permissions #{invalid_member_permissions |> Enum.join(", ")}"
    end

    @member_permissions
    |> Enum.reduce(0, fn {val, member_permission}, acc ->
      if(member_permissions[member_permission], do: val, else: 0) + acc
    end)
  end

  def has_member_permission?(%Hub{} = hub, member_permission) do
    case @member_permissions
         |> Enum.find(fn {_, member_permission_name} -> member_permission_name == member_permission end) do
      nil -> raise ArgumentError, "Invalid permission #{member_permission}"
      {val, _} -> (hub.member_permissions &&& val) > 0
    end
  end

  def member_permissions_for_hub(%Hub{} = hub) do
    hub.member_permissions |> BitFieldUtils.permissions_to_map(@member_permissions)
  end

  # The account argument here can be a Ret.Account, a Ret.OAuthProvider or nil.
  def perms_for_account(%Ret.Hub{} = hub, account) do
    %{
      join_hub: account |> can?(join_hub(hub)),
      update_hub: account |> can?(update_hub(hub)),
      update_hub_privacy: account |> can?(update_hub_privacy(hub)),
      update_roles: account |> can?(update_roles(hub)),
      close_hub: account |> can?(close_hub(hub)),
      embed_hub: account |> can?(embed_hub(hub)),
      kick_users: account |> can?(kick_users(hub)),
      mute_users: account |> can?(mute_users(hub)),
      spawn_camera: account |> can?(spawn_camera(hub)),
      spawn_drawing: account |> can?(spawn_drawing(hub)),
      spawn_and_move_media: account |> can?(spawn_and_move_media(hub)),
      pin_objects: account |> can?(pin_objects(hub))
    }
  end

  def roles_for_account(%Ret.Hub{}, nil),
    do: %{owner: false, creator: false, signed_in: false}

  def roles_for_account(%Ret.Hub{} = hub, account),
    do: %{owner: hub |> is_owner?(account.account_id), creator: hub |> is_creator?(account.account_id), signed_in: true}
end

defimpl Canada.Can, for: Ret.Account do
  alias Ret.{Hub}
  @owner_actions [:update_hub, :close_hub, :embed_hub, :kick_users, :mute_users]
  @object_actions [:spawn_and_move_media, :spawn_camera, :spawn_drawing, :pin_objects]
  @creator_actions [:update_roles]

  # Always deny access to non-enterable hubs
  def can?(%Ret.Account{}, :join_hub, %Ret.Hub{entry_mode: :deny}), do: false

  def can?(%Ret.Account{} = account, :update_hub_privacy, %Ret.Hub{} = hub) do
    owners_can_change_privacy = Ret.AppConfig.get_config_bool("features|public_rooms")
    account.is_admin or (owners_can_change_privacy and can?(account, :update_hub, hub))
  end

  # Bound hubs - Join perm
  def can?(%Ret.Account{} = account, :join_hub, %Ret.Hub{hub_bindings: hub_bindings})
      when hub_bindings |> length > 0 do
    hub_bindings |> Enum.any?(&(account |> Ret.HubBinding.member_of_channel?(&1)))
  end

  # Bound hubs - Manage actions
  def can?(%Ret.Account{} = account, action, %Ret.Hub{hub_bindings: hub_bindings})
      when action in [:update_hub, :close_hub] and hub_bindings |> length > 0 do
    hub_bindings |> Enum.any?(&(account |> Ret.HubBinding.can_manage_channel?(&1)))
  end

  # Bound hubs - Moderator actions
  def can?(%Ret.Account{} = account, action, %Ret.Hub{hub_bindings: hub_bindings})
      when hub_bindings |> length > 0 and action in [:kick_users, :mute_users] do
    hub_bindings |> Enum.any?(&(account |> Ret.HubBinding.can_moderate_users?(&1)))
  end

  # Bound hubs - Object permissions
  def can?(%Ret.Account{} = account, action, %Ret.Hub{hub_bindings: hub_bindings} = hub)
      when hub_bindings |> length > 0 and action in @object_actions do
    is_moderator = hub_bindings |> Enum.any?(&(account |> Ret.HubBinding.can_moderate_users?(&1)))

    if is_moderator do
      true
    else
      is_member = hub_bindings |> Enum.any?(&(account |> Ret.HubBinding.member_of_channel?(&1)))
      is_member and hub |> Hub.has_member_permission?(action)
    end
  end

  # Bound hubs - Always prevent embedding and role assignment (since it's dictated by binding)
  def can?(%Ret.Account{}, action, %Ret.Hub{hub_bindings: hub_bindings})
      when hub_bindings |> length > 0 and action in [:embed_hub, :update_roles],
      do: false

  # Unbound hubs - Anyone can join an unbound hub
  def can?(_account, :join_hub, %Ret.Hub{hub_bindings: []}), do: true

  # Unbound hubs - Creator can perform creator actions
  def can?(%Ret.Account{account_id: account_id}, action, %Ret.Hub{
        created_by_account_id: created_by_account_id,
        hub_bindings: []
      })
      when action in @creator_actions and created_by_account_id != nil and created_by_account_id == account_id,
      do: true

  # Unbound hubs - Owners can perform special actions
  def can?(%Ret.Account{account_id: account_id}, action, %Ret.Hub{hub_bindings: []} = hub)
      when action in @owner_actions,
      do: hub |> Ret.Hub.is_owner?(account_id)

  # Unbound hubs - Object actions can be performed if granted in member permissions or if account is an owner
  def can?(%Ret.Account{account_id: account_id}, action, %Hub{hub_bindings: []} = hub) when action in @object_actions do
    hub |> Hub.has_member_permission?(action) or hub |> Ret.Hub.is_owner?(account_id)
  end

  # Deny permissions for any other case that falls through
  def can?(_, _, _), do: false
end

# Perms for oauth users that do not have a hubs account
defimpl Canada.Can, for: Ret.OAuthProvider do
  alias Ret.{Hub}
  @object_actions [:spawn_and_move_media, :spawn_camera, :spawn_drawing, :pin_objects]
  @special_actions [:update_hub, :update_roles, :close_hub, :embed_hub, :kick_users, :mute_users]

  # Always deny access to non-enterable hubs
  def can?(%Ret.OAuthProvider{}, :join_hub, %Ret.Hub{entry_mode: :deny}), do: false

  # OAuthProvider users cannot perform special actions
  def can?(%Ret.OAuthProvider{}, action, %Ret.Hub{}) when action in @special_actions,
    do: false

  def can?(%Ret.OAuthProvider{} = oauth_provider, :join_hub, %Ret.Hub{hub_bindings: hub_bindings})
      when hub_bindings |> length > 0 do
    hub_bindings |> Enum.any?(&(oauth_provider |> Ret.HubBinding.member_of_channel?(&1)))
  end

  # Object permissions for OAuthProvider users are based on member permission settings
  def can?(%Ret.OAuthProvider{} = oauth_provider, action, %Ret.Hub{hub_bindings: hub_bindings} = hub)
      when action in @object_actions do
    is_member = hub_bindings |> Enum.any?(&(oauth_provider |> Ret.HubBinding.member_of_channel?(&1)))
    is_member and hub |> Hub.has_member_permission?(action)
  end

  def can?(_, _, _), do: false
end

# Permissions for un-authenticated clients
defimpl Canada.Can, for: Atom do
  alias Ret.{Hub}
  @object_actions [:spawn_and_move_media, :spawn_camera, :spawn_drawing, :pin_objects]

  # Always deny access to non-enterable hubs
  def can?(_, :join_hub, %Ret.Hub{entry_mode: :deny}), do: false

  # Anyone can join an unbound hub
  def can?(_, :join_hub, %Ret.Hub{hub_bindings: []}), do: true

  # Object permissions for anonymous users are based on member permission settings
  def can?(_account, action, hub) when action in @object_actions do
    hub |> Hub.has_member_permission?(action)
  end

  def can?(_, _, _), do: false
end
