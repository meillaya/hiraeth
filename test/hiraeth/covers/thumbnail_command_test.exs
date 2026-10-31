defmodule Hiraeth.Covers.ThumbnailCommandTest do
  use ExUnit.Case, async: false

  alias Hiraeth.Covers

  setup do
    original_path = System.get_env("PATH")
    temp_dir = Path.join(System.tmp_dir!(), "hiraeth-thumb-#{System.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      restore_path(original_path)
      File.rm_rf!(temp_dir)
    end)

    System.put_env("PATH", temp_dir <> ":" <> original_path)
    %{temp_dir: temp_dir}
  end

  test "prefers magick when both programs are available", %{temp_dir: temp_dir} do
    fake_executable!(temp_dir, "magick")
    fake_executable!(temp_dir, "convert")

    assert {"magick", path} = Covers.thumbnail_command()
    assert path == Path.join(temp_dir, "magick")
  end

  test "falls back to convert for ImageMagick 6", %{temp_dir: temp_dir} do
    fake_executable!(temp_dir, "convert")

    assert {"convert", path} = Covers.thumbnail_command()
    assert path == Path.join(temp_dir, "convert")
  end

  test "returns nil when no ImageMagick command is available", %{temp_dir: _temp_dir} do
    assert Covers.thumbnail_command() == nil
  end

  test "generate_thumbnail writes the output path through the selected command", %{
    temp_dir: temp_dir
  } do
    fake_executable!(temp_dir, "convert")

    source = Path.join(temp_dir, "source.jpg")
    output = Path.join(temp_dir, "out-thumb.jpg")
    File.write!(source, "source image")

    assert {:ok, ^output} = Covers.generate_thumbnail(source, output)
    assert File.read!(output) == "fake thumbnail"
  end

  defp fake_executable!(dir, name) do
    path = Path.join(dir, name)

    File.write!(path, """
    #!/bin/sh
    last=""
    for arg in "$@"; do last="$arg"; done
    printf 'fake thumbnail' > "$last"
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp restore_path(nil), do: System.delete_env("PATH")
  defp restore_path(path), do: System.put_env("PATH", path)
end
