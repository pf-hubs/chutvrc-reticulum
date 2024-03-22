defmodule Ret.Repo.Migrations.AddFullAvatarFlagToHubs do
  use Ecto.Migration

  def change do
    alter table("hubs") do
      add :allow_fullbody_avatar, :boolean, null: false, default: true
    end
  end
end
