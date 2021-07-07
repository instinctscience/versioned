use Mix.Config

config :versioned,
  ecto_repos: [Versioned.Test.Repo],
  repo: Versioned.Test.Repo

config :versioned, Versioned.Test.Repo,
  database: "versioned_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  priv: "test/support/priv"

config :logger, level: :info
