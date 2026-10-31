defmodule HiraethWeb.RedirectController do
  @moduledoc """
  Permanent browser redirects for publisher slugs folded into a parent press.

  Fum d'Estampa, Phoneme Media, La Reunion, and A Strange Object are catalogued
  under Deep Vellum. Their old publisher URLs redirect to the parent page so
  existing links keep working.
  """

  use HiraethWeb, :controller

  @doc false
  def publisher_group(conn, _params) do
    conn
    |> redirect(to: "/publishers/deep-vellum")
    |> halt()
  end
end
