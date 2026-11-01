defmodule HiraethWeb.CatalogComponentsCoverTest do
  @moduledoc "The catalog cover renders a responsive WebP/JPEG picture element."

  use HiraethWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HiraethWeb.CatalogComponents

  test "emits a picture element with WebP and JPEG srcsets" do
    book = %{
      slug: "responsive-cover",
      title: "Responsive Cover",
      publisher: "Test Press",
      authors: [],
      cover: %{
        thumbnail_url: "/covers/cache/cover-400w-abc.jpg",
        public_url: "/covers/cache/cover.jpg",
        responsive_variants: [
          %{format: "webp", width: 200, url: "/covers/cache/cover-200w-a.webp"},
          %{format: "jpg", width: 200, url: "/covers/cache/cover-200w-b.jpg"},
          %{format: "webp", width: 400, url: "/covers/cache/cover-400w-c.webp"},
          %{format: "jpg", width: 400, url: "/covers/cache/cover-400w-d.jpg"}
        ]
      }
    }

    html = render_component(&CatalogComponents.catalog_cover/1, book: book, variant: :card)

    assert html =~ ~s(type="image/webp")
    assert html =~ ~s(/covers/cache/cover-200w-a.webp 200w)
    assert html =~ ~s(/covers/cache/cover-400w-c.webp 400w)
    assert html =~ ~s(src="/covers/cache/cover-400w-d.jpg")

    assert html =~
             ~s(srcset="/covers/cache/cover-200w-b.jpg 200w, /covers/cache/cover-400w-d.jpg 400w")

    assert html =~ ~s|sizes="(max-width: 760px) 45vw, 320px"|
  end
end
