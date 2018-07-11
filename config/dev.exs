use Mix.Config

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with brunch.io to recompile .js and .css sources.
config :ret, RetWeb.Endpoint,
  url: [scheme: "https", host: "hubs.local", port: 4000],
  static_url: [scheme: "https", host: "hubs.local", port: 4000],
  https: [
    port: 4000,
    otp_app: :ret,
    keyfile: "#{System.get_env("PWD")}/priv/dev-ssl.key",
    certfile: "#{System.get_env("PWD")}/priv/dev-ssl.cert"
  ],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  secret_key_base: "txlMOtlaY5x3crvOCko4uV5PM29ul3zGo1oBGNO3cDXx+7GHLKqt0gR9qzgThxb5",
  watchers: [
    node: [
      "node_modules/brunch/bin/brunch",
      "watch",
      "--stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# command from your terminal:
#
#     openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=www.example.com" -keyout priv/server.key -out priv/server.pem
#
# The `http:` config above can be replaced with:
#
#     https: [port: 4000, keyfile: "priv/server.key", certfile: "priv/server.pem"],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :ret, RetWeb.Endpoint,
  # static_url: [scheme: "https", host: "assets-prod.reticulum.io", port: 443],
  live_reload: [
    patterns: [
      ~r{priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$},
      ~r{priv/gettext/.*(po)$},
      ~r{lib/ret_web/views/.*(ex)$},
      ~r{lib/ret_web/templates/.*(eex)$}
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Configure your database
config :ret, Ret.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: "postgres",
  password: "postgres",
  database: "ret_dev",
  hostname: "localhost",
  template: "template0",
  pool_size: 10

config :ret, RetWeb.Plugs.HeaderAuthorization,
  header_name: "x-ret-admin-access-key",
  header_value: "admin-only"

# Allow any origin for API access in dev
config :cors_plug, origin: ["*"]

config :ret,
  farspark_signature_key:
    "248cf801c4f5d6fd70c1b0dfea8dedeb57adafa7821027d546f016efef5a501bd8168c8479d33b466199d0ac68c71bb71b68c27537102a63cd70776aa83bca76",
  farspark_signature_salt:
    "da914bb89e332b2a815a667875584d067b698fe1f6f5c61d98384dc74d2ed85b67eea0a51325afb9d9c7d798f4bbbd630102a261e152aceb13d9469b02da6b31",
  farspark_host: "https://farspark-dev.reticulum.io"

config :ret, Ret.MediaResolver,
  giphy_api_key: nil,
  deviantart_client_id: nil,
  deviantart_client_secret: nil,
  imgur_mashape_api_key: nil,
  imgur_client_id: nil,
  google_poly_api_key: nil,
  sketchfab_api_key: nil,
  ytdl_host: "http://localhost:9191"
