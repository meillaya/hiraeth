defmodule Hiraeth.ServiceRole do
  @moduledoc """
  Deployment role for the shared release image.

  `web` serves HTTP and never runs Oban; `worker` runs Oban and never starts the
  endpoint; `all` keeps the single-process development/test topology.
  """

  @roles [:all, :web, :worker]

  @spec current() :: :all | :web | :worker
  def current do
    Application.get_env(:hiraeth, :service_role, :all)
    |> normalize()
  end

  @spec web?() :: boolean()
  def web?, do: current() in [:all, :web]

  @spec worker?() :: boolean()
  def worker?, do: current() in [:all, :worker]

  @spec parse(String.t() | nil) :: :all | :web | :worker
  def parse(value) when value in ["web", "worker", "all"], do: String.to_existing_atom(value)
  def parse(_value), do: :web

  defp normalize(role) when role in @roles, do: role
  defp normalize(_role), do: :all
end
