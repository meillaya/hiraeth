defmodule HiraethWeb.CatalogPageHTML do
  use HiraethWeb, :html

  embed_templates "catalog_page_html/*"

  def format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  def format_count(count), do: to_string(count)

  def author_line(book) do
    book
    |> Map.get(:authors, [])
    |> List.wrap()
    |> Enum.map(& &1[:name])
    |> Enum.reject(fn name ->
      is_nil(name) or HiraethWeb.CatalogText.unknown_contributor?(name)
    end)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      names -> names
    end
  end

  def book_year(%{published_on: %Date{} = date}), do: to_string(date.year)
  def book_year(_book), do: ""

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
