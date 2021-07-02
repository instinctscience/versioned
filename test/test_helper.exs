require Logger

ExUnit.start()

# Ensure that symlink to custom ecto priv directory exists
source = Versioned.Test.Repo.config()[:priv]
target = Application.app_dir(:versioned, source)
File.rm_rf(target)
File.mkdir_p(target)
File.rmdir(target)
:ok = :file.make_symlink(Path.expand(source), target)

Logger.info("Running migrations...")

Mix.Task.run("ecto.drop", ~w(--quiet))
Mix.Task.run("ecto.create", ~w(--quiet))
Mix.Task.run("ecto.migrate", ~w(--quiet))

{:ok, _pid} = Versioned.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(Versioned.Test.Repo, :manual)
