defmodule HiraethWeb.CatalogPageHTML do
  use HiraethWeb, :html

  embed_templates "catalog_page_html/*"

  def format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  def format_count(count), do: to_string(count)

  def sample_book(%{slug: slug, cover_sample: %{title: title, cover: cover}})
      when is_binary(title) and not is_nil(cover) do
    %{
      slug: "press-sample-#{slug}",
      title: title,
      publisher: nil,
      authors: [],
      published_on: nil,
      cover: cover
    }
  end

  def sample_book(_publisher), do: nil

  def initial(name) when is_binary(name) do
    name |> String.first() |> Kernel.||("H") |> String.upcase()
  end
end
