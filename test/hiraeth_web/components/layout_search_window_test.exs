defmodule HiraethWeb.LayoutSearchWindowTest do
  @moduledoc "The public shell mounts the global search window on every page."

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HiraethWeb.Layouts

  test "renders the header trigger and the search dialog" do
    html = render_shell()

    assert html =~ ~s(data-search-open)
    assert html =~ ~s(aria-controls="search-window")
    assert html =~ ~s(id="search-window")
    assert html =~ ~s(aria-labelledby="search-window-title")
    assert html =~ ~s(action="/search")
    assert html =~ ~s(name="q")
    assert html =~ ~s(data-search-results)
    assert html =~ ~s(data-search-all)
  end

  test "the header control keeps a plain link fallback" do
    html = render_shell()

    assert html =~ ~s(href="/search")
    assert html =~ ~s(aria-haspopup="dialog")
  end

  defp render_shell do
    render_component(&Layouts.app/1, %{
      flash: %{},
      inner_block: [%{inner_block: fn _, _ -> "content" end}]
    })
  end
end
