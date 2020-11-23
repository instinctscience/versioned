defmodule Versioned.Test.Repo do
  use Ecto.Repo, otp_app: :versioned, adapter: Ecto.Adapters.Postgres
end
