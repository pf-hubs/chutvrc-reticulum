defmodule Ret.Repo.Migrations.CreateServerConfigsTable do
  use Ecto.Migration

  def change do
    create table(:server_configs, primary_key: false) do
      add :server_config_id, :bigint, default: fragment("ret0.next_id()"), primary_key: true
      add :key, :string, null: false
      add :value, :jsonb
      add :owned_file_id, :bigint

      timestamps()
    end

    create unique_index(:server_configs, [:key])
  end
end
