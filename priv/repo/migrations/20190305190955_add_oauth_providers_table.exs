defmodule Ret.Repo.Migrations.AddOauthProvidersTable do
  use Ret.Migration

  def change do
    Ret.OAuthProvider.Source.create_type()

    create table(:oauth_providers, prefix: "ret0", primary_key: false) do
      add(:oauth_provider_id, :bigint, default: fragment("ret0.next_id()"), primary_key: true)
      add(:account_id, :bigint, null: false)
      add(:source, :oauth_provider_source, null: false)
      add(:provider_account_id, :string, null: false)

      timestamps()
    end

    create(index(:oauth_providers, [:source, :account_id], unique: true))
    create(index(:oauth_providers, [:source, :provider_account_id], unique: true))
  end
end
