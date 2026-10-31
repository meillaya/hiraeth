defmodule HiraethWeb.SecurityHeadersTest do
  @moduledoc """
  Asserts the browser pipeline still ships the self-contained page contract.

  The CSP is the one defense that keeps public pages from loading remote
  scripts, fonts, or images. It used to be exempted in Sobelow; this test keeps
  the header from disappearing without a failing gate.
  """

  use HiraethWeb.ConnCase, async: true

  test "browser responses carry the self-contained content security policy", %{conn: conn} do
    conn = get(conn, "/browse")

    assert [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "default-src 'self'"
    assert csp =~ "script-src 'self'"
    assert csp =~ "img-src 'self' data:"
    assert csp =~ "object-src 'none'"
    assert csp =~ "frame-ancestors 'self'"
    refute csp =~ "unsafe-eval"
    refute csp =~ "http:"
    refute csp =~ "https:"
  end
end
