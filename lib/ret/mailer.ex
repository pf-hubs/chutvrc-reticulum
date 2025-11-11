defmodule Ret.Mailer do
  use Bamboo.Mailer, otp_app: :ret
  require Logger

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
    default_mailer_config = Application.get_env(:ret, Ret.Mailer, %{})

    config = %{
      username: Ret.ServerConfig.get_cached_config_value("email|username") || default_mailer_config[:username],
      password: Ret.ServerConfig.get_cached_config_value("email|password") || default_mailer_config[:password],
      server: Ret.ServerConfig.get_cached_config_value("email|server") || default_mailer_config[:server],
      from: Ret.ServerConfig.get_cached_config_value("email|from") || default_mailer_config[:username],
      smtp_port: Ret.ServerConfig.get_cached_config_value("email|port") || default_mailer_config[:port]
    }

    Ret.Mailer.deliver_now(email, config: config)
  end
end
