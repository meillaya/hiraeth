defmodule Hiraeth.Covers.PolicyTest do
  use ExUnit.Case, async: true

  alias Hiraeth.Covers.Policy

  test "the newest print cover wins, so a reissue replaces the retired cover" do
    old = edition("paperback", ~D[2000-07-01], "old")
    reissue = edition("paperback", ~D[2027-08-24], "reissue")

    assert Policy.cover_edition([old, reissue]).source_url == "reissue"
    assert Policy.cover_edition([reissue, old]).source_url == "reissue"
  end

  test "date ordering is chronological, not struct term order" do
    old = edition("paperback", ~D[2013-03-05], "old")
    new = edition("paperback", ~D[2027-05-04], "new")

    assert Policy.cover_edition([old, new]).source_url == "new"
  end

  test "a print edition beats a newer ebook edition" do
    print = edition("paperback", ~D[2000-07-01], "print")
    ebook = edition("ebook", ~D[2027-08-24], "ebook")

    assert Policy.cover_edition([print, ebook]).source_url == "print"
  end

  test "a work with no displayable print cover falls back to one non-print cover" do
    ebook = edition("ebook", ~D[2027-08-24], "ebook")

    assert Policy.cover_edition([ebook]).source_url == "ebook"
  end

  test "an uncached print cover does not beat a displayable ebook cover" do
    print = edition("paperback", ~D[2027-08-24], "print", cover: nil)
    ebook = edition("ebook", ~D[2020-01-01], "ebook")

    assert Policy.cover_edition([print, ebook]).source_url == "ebook"
  end

  test "paperback wins before hardcover on the same date" do
    hardcover = edition("hardcover", ~D[2026-01-01], "hardcover")
    paperback = edition("paperback", ~D[2026-01-01], "paperback")

    assert Policy.cover_edition([hardcover, paperback]).source_url == "paperback"
  end

  test "nil when no edition has a displayable cover" do
    assert Policy.cover_edition([edition("paperback", ~D[2026-01-01], "x", cover: nil)]) == nil
    assert Policy.cover_edition([]) == nil
  end

  test "print formats are the canonical cover formats" do
    assert Policy.print_formats() == ["paperback", "hardcover"]
    assert "ebook" not in Policy.print_formats()
  end

  defp edition(format, published_on, source_url, opts \\ []) do
    cover =
      Keyword.get(opts, :cover, %{
        public_url: "/covers/cache/#{source_url}.jpg",
        thumbnail_url: "/covers/cache/#{source_url}-thumb.jpg",
        source_url: source_url
      })

    %{
      format: format,
      published_on: published_on,
      slug: "edition-#{source_url}",
      cover: cover
    }
  end
end
