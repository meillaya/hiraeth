defmodule HiraethWeb.AdminHTML do
  use HiraethWeb, :html

  embed_templates "admin_html/*"

  def format_count(count) when is_integer(count) do
    count
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  def format_count(count), do: to_string(count)

  def badge_class("approved"), do: "admin-badge admin-badge--approved"
  def badge_class("rejected"), do: "admin-badge admin-badge--rejected"
  def badge_class("ignored"), do: "admin-badge admin-badge--ignored"
  def badge_class(_decision), do: "admin-badge"

  def timestamp(nil), do: "—"

  def timestamp(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")
  def timestamp(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  def timestamp(value), do: to_string(value)
end
