defmodule Ret.Repo.Migrations.AddSoraAccessTokenToHubs do
  use Ecto.Migration

  def change do
    alter table("hubs") do
      add :sfu, :integer, null: false, default: 0
      add :sora_access_token, :string
    end
  end
end
