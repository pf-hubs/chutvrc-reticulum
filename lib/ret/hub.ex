defmodule Ret.Hub do
  use Ecto.Schema
  import Ecto.Changeset
  alias Ret.Hub
  use Bitwise

  @schema_prefix "ret0"
  @primary_key { :hub_id, :integer, [] }

  schema "hubs" do
    field :hub_sid, :string
    field :default_environment_gltf_bundle_url, :string

    timestamps()
  end

  def changeset(%Hub{} = hub, attrs) do
    hub
    |> cast(attrs, [:hub_sid, :default_environment_gltf_bundle_url])
    |> validate_required([:hub_sid, :default_environment_gltf_bundle_url])
  end

  def janus_sfu_room_for_hub(hub) do
    hub.hub_id &&& 0xFFFFFFFF
  end
end
