defmodule WeGoNext.Repo do
  use Ecto.Repo,
    otp_app: :we_go_next,
    adapter: Ecto.Adapters.Postgres
end
