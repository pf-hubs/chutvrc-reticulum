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

  def deliver_now_with_config(email) do
    config = %{
      username: Ret.ServerConfig.get_cached_config_value("email|username"),
      password: Ret.ServerConfig.get_cached_config_value("email|password"),
      server: Ret.ServerConfig.get_cached_config_value("email|server"),
      from: Ret.ServerConfig.get_cached_config_value("email|from"),
      smtp_port: Ret.ServerConfig.get_cached_config_value("email|port")
    }

    Ret.Mailer.deliver_now(email, config: config)
  end
end
