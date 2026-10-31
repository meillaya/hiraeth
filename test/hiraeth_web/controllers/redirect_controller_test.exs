defmodule HiraethWeb.RedirectControllerTest do
  use HiraethWeb.ConnCase, async: true

  test "folded imprint publisher slugs redirect to Deep Vellum", %{conn: conn} do
    for slug <- ~w(a-strange-object fum-destampa la-reunion phoneme-media) do
      conn = get(conn, "/publishers/#{slug}")

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/publishers/deep-vellum"]
    end
  end
end
