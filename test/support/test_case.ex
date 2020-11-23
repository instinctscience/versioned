defmodule Versioned.TestCase do
  @moduledoc "Test case, setting up a shared sandbox."
  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox
  alias Versioned.Test.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end
end
