defmodule WeGoNext.Repo.Migrations.AddWindowCaptureToSilverDeath do
  use Ecto.Migration

  def change do
    alter table(:death, prefix: "silver") do
      # Fixed-seconds death window capture: interleaved damage/heal/usage
      # rows tagged by "kind", time-ascending; damage_recap stays the
      # damage-only newest-first view of the same window.
      add(:window_ms, :integer)
      add(:window_truncated, :boolean, null: false, default: false)
      add(:window_events, {:array, :map}, null: false, default: [])
    end
  end
end
