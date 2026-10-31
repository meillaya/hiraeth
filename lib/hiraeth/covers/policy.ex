defmodule Hiraeth.Covers.Policy do
  @moduledoc """
  The single decision for which edition supplies a work's public cover.

  A work can have several editions: an original printing, a reissue, an ebook,
  an audiobook. The catalog shows exactly one cover per work, and this module
  owns that choice everywhere, so the browser, the JSON API, search results, and
  publisher cards cannot disagree:

    1. Print editions are canonical. Among displayable print covers, the newest
       printing wins (paperback before hardcover on the same date). A reissue
       therefore replaces the retired cover with the current one.
    2. A work with no displayable print cover falls back to its newest
       displayable non-print edition, so an ebook-only title still has one cover.
       The fallback is per work, never a mix of formats.
    3. A cover belongs to exactly one edition. Cards, the hero, and API
       responses all receive that same cover object.

  "Displayable" is decided by the read path: policy-allowed, cache-allowed, and
  backed by a cached original or the durable store. This module is pure and
  works on projected editions, which keeps the rule testable without a database.
  """

  @print_formats ~w(paperback hardcover)
  @fallback_formats ~w(ebook audiobook)

  @type cover :: map()
  @type edition :: %{
          required(:format) => String.t() | nil,
          required(:published_on) => Date.t() | nil,
          required(:slug) => String.t(),
          required(:cover) => cover() | nil
        }

  @doc "Formats whose cover art is canonical for a work."
  @spec print_formats() :: [String.t()]
  def print_formats, do: @print_formats

  @doc "Formats used only when the work has no displayable print cover."
  @spec fallback_formats() :: [String.t()]
  def fallback_formats, do: @fallback_formats

  @doc """
  Returns the one cover that represents `editions`, or nil when none is
  displayable.
  """
  @spec cover_edition([edition()]) :: cover() | nil
  def cover_edition(editions) do
    editions
    |> Enum.filter(&displayable_cover?(&1.cover))
    |> Enum.sort_by(&selection_key/1, :desc)
    |> case do
      [edition | _rest] -> edition.cover
      [] -> nil
    end
  end

  @doc "True when the cover has a same-origin URL the browser may render."
  @spec displayable_cover?(cover() | nil) :: boolean()
  def displayable_cover?(nil), do: false

  def displayable_cover?(cover) do
    not is_nil(Map.get(cover, :public_url)) or not is_nil(Map.get(cover, :thumbnail_url))
  end

  defp selection_key(edition) do
    {
      print_rank(edition.format),
      published_on_days(edition.published_on),
      -format_rank(edition.format),
      edition.slug
    }
  end

  # Dates are structs, so Erlang term ordering is not chronological. Convert to
  # gregorian days before sorting; a missing date sorts oldest.
  defp published_on_days(nil), do: 0
  defp published_on_days(%Date{} = date), do: Date.to_gregorian_days(date)

  defp print_rank(format) when format in @print_formats, do: 1
  defp print_rank(_format), do: 0

  defp format_rank("paperback"), do: 0
  defp format_rank("hardcover"), do: 1
  defp format_rank("ebook"), do: 2
  defp format_rank("audiobook"), do: 3
  defp format_rank(_format), do: 9
end
