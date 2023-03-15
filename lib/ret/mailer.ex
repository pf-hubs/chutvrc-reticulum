defmodule Ret.Mailer do
  use Bamboo.Mailer, otp_app: :ret

  def update_config(mailer_config = %{}) do
    # mailer_config = %{
    #   server: "smtp.xxx.com",
    #   port: 587,
    #   username: "xxx@yyy.zzz",
    #   password: "password"
    # }
    old_mailer_config = Application.get_env(:ret, Ret.Mailer, %{})
    Application.put_env(:ret, Ret.Mailer, Map.merge(Enum.into(old_mailer_config, %{}), mailer_config))
  end
end
