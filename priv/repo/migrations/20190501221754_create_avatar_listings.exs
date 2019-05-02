defmodule Ret.Repo.Migrations.CreateAvatarListings do
  use Ecto.Migration

  def change do
    Ret.AvatarListing.State.create_type()

    create table(:avatar_listings, prefix: "ret0", primary_key: false) do
      add(:avatar_listing_id, :bigint, default: fragment("ret0.next_id()"), primary_key: true)
      add(:avatar_listing_sid, :string)
      add(:slug, :string, null: false)
      add(:order, :integer)
      add(:state, :avatar_listing_state, null: false, default: "active")
      add(:tags, :jsonb)
      add(:avatar_id, :bigint, null: false)
      timestamps()

      add(:name, :string, null: false)
      add(:description, :string)
      add(:attributions, :jsonb)

      add(:parent_avatar_listing_id, references(:avatar_listings, column: :avatar_listing_id))

      add(:gltf_owned_file_id, references(:owned_files, column: :owned_file_id))
      add(:bin_owned_file_id, references(:owned_files, column: :owned_file_id))
      add(:thumbnail_owned_file_id, references(:owned_files, column: :owned_file_id))

      add(:base_map_owned_file_id, references(:owned_files, column: :owned_file_id))
      add(:emissive_map_owned_file_id, references(:owned_files, column: :owned_file_id))
      add(:normal_map_owned_file_id, references(:owned_files, column: :owned_file_id))
      add(:orm_map_owned_file_id, references(:owned_files, column: :owned_file_id))
    end

    create(index(:avatar_listings, [:avatar_listing_sid], unique: true))

    alter table(:avatars) do
      add(:parent_avatar_listing_id, references(:avatar_listings, column: :avatar_listing_id))
    end
    drop constraint(:avatars, :gltf_or_parent)
    create constraint(:avatars, :gltf_or_parent_or_parent_listing, check: "parent_avatar_id is not null or parent_avatar_listing_id is not null or (gltf_owned_file_id is not null and bin_owned_file_id is not null)")
  end
end
