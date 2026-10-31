defmodule Hiraeth.Covers.CachePrunerTest do
  @moduledoc "The local cover cache stays under its configured byte cap."

  use ExUnit.Case, async: true

  alias Hiraeth.Covers.CachePruner

  test "deletes oldest files until the cache fits the cap" do
    root =
      Path.join(System.tmp_dir!(), "hiraeth-cover-pruner-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    files =
      for {name, day} <- [
            {"oldest.jpg", 1},
            {"older.jpg", 2},
            {"newer.jpg", 3},
            {"newest.jpg", 4}
          ] do
        path = Path.join(root, name)
        File.write!(path, :binary.copy("x", 100))
        File.touch!(path, {{2026, 1, day}, {0, 0, 0}})
        {name, path}
      end

    assert {:ok, 2} = CachePruner.prune!(cache_root: root, max_bytes: 250)

    assert [
             {"oldest.jpg", oldest_path},
             {"older.jpg", older_path},
             {"newer.jpg", newer_path},
             {"newest.jpg", newest_path}
           ] =
             files

    refute File.exists?(oldest_path)
    refute File.exists?(older_path)
    assert File.exists?(newer_path)
    assert File.exists?(newest_path)
  end

  test "keeps a cache already under the cap" do
    root =
      Path.join(System.tmp_dir!(), "hiraeth-cover-pruner-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "cover.jpg")
    File.write!(path, :binary.copy("x", 100))

    assert {:ok, 0} = CachePruner.prune!(cache_root: root, max_bytes: 1024)
    assert File.exists?(path)
  end
end
