defmodule HiraethWeb.CatalogText do
  @moduledoc """
  Presentation-safe rendering of sourced publisher prose.

  Publisher descriptions arrive as WordPress/Shopify HTML, shortcode soup, and
  HTML entities. Public pages must never render that markup or its control
  fragments, so every excerpt passes through one cleaner at the web boundary.
  The source record stays untouched for provenance.
  """

  @shortcode ~r/\[\/?[a-zA-Z][^\]]*\]/
  @tag ~r/<[^>]*>/u
  @entity ~r/&(?:#(x?)([0-9A-Fa-f]+)|([a-zA-Z][a-zA-Z0-9]+));/
  @known_entities %{
    "amp" => "&",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "ndash" => "–",
    "mdash" => "—",
    "hellip" => "…",
    "rsquo" => "’",
    "lsquo" => "‘",
    "ldquo" => "“",
    "rdquo" => "”",
    "copy" => "©",
    "reg" => "®",
    "trade" => "™"
  }

  @unknown_contributor ~r/^unknown( contributor| author)?$/i

  @doc """
  Returns plain text, collapsed and optionally truncated on a word boundary.

  A `nil` or blank description stays `nil` so callers can omit the element
  instead of rendering an empty paragraph.
  """
  @spec plain(String.t() | nil, pos_integer() | nil) :: String.t() | nil
  def plain(text, limit \\ nil)

  def plain(nil, _limit), do: nil

  def plain(text, limit) when is_binary(text) do
    cleaned =
      text
      |> String.replace(@shortcode, " ")
      |> String.replace(@tag, " ")
      |> decode_entities()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    case cleaned do
      "" -> nil
      text when is_integer(limit) and limit > 0 -> truncate(text, limit)
      text -> text
    end
  end

  @doc "True for placeholder contributor names that should never render."
  @spec unknown_contributor?(String.t() | nil) :: boolean()
  def unknown_contributor?(name) when is_binary(name) do
    Regex.match?(@unknown_contributor, String.trim(name))
  end

  def unknown_contributor?(_name), do: false

  defp truncate(text, limit) do
    if String.length(text) <= limit do
      text
    else
      text
      |> String.slice(0, limit)
      |> String.replace(~r/\s+\S*$/u, "")
      |> Kernel.<>("…")
    end
  end

  defp decode_entities(text) do
    Regex.replace(@entity, text, fn whole, hex?, digits, name ->
      cond do
        is_binary(name) -> Map.get(@known_entities, name, whole)
        hex? == "x" -> codepoint(digits, 16, whole)
        true -> codepoint(digits, 10, whole)
      end
    end)
  end

  defp codepoint(digits, base, fallback) do
    case Integer.parse(digits, base) do
      {value, ""} when value in 0..0x10FFFF and value not in 0xD800..0xDFFF ->
        <<value::utf8>>

      _invalid ->
        fallback
    end
  end
end
