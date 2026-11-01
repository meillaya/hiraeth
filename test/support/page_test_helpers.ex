defmodule HiraethWeb.PageTestHelpers do
  @moduledoc "Small helpers for assertions against controller-rendered HTML."

  def page(conn, path) do
    conn = Phoenix.ConnTest.dispatch(conn, HiraethWeb.Endpoint, :get, path)
    {Phoenix.ConnTest.html_response(conn, 200), conn}
  end

  def page_has?(html, selector, text \\ nil) do
    document = LazyHTML.from_fragment(html)

    document
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> Enum.any?(fn node ->
      is_nil(text) or String.contains?(node_text(node), text)
    end)
  end

  def page_refute?(html, selector, text \\ nil), do: not page_has?(html, selector, text)

  defp node_text({_tag, _attrs, children}) do
    children
    |> List.wrap()
    |> Enum.map_join(fn
      child when is_binary(child) -> child
      child -> node_text(child)
    end)
  end

  defp node_text(text) when is_binary(text), do: text
end
