defmodule Ret.Repo.Migrations.CreateHubsAdmin do
  use Ecto.Migration

  def up do
    execute "select ret0_admin.create_or_replace_admin_view('hubs')"

    execute "grant select, insert, update, delete on ret0_admin.hubs to ret_admin"
  end

  def down do
    execute "drop view ret0_admin.hubs"
  end
end
