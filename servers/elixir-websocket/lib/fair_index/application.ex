defmodule FairIndex.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [{FairIndex.Server, 80}]
    opts = [strategy: :one_for_one, name: FairIndex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
