defmodule WeGoNext.SourceData.WowAnalyzerTimelineCandidate do
  @moduledoc """
  Parsed WowAnalyzer mechanic source row inferred from an encounter timeline entry.

  These rows are source evidence. They are not active mechanic rules and do not
  directly produce gold facts. Code-defined raid mechanic catalogs decide which
  timeline hints are relevant to active rule criteria.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.SourceData.SourceImport

  @schema_prefix "source_data"
  @timeline_types ~w(ability debuff)
  @confidence_levels ~w(high medium low)
  @review_statuses ~w(inferred accepted rejected ignored overridden)

  schema "wowanalyzer_timeline_candidate" do
    belongs_to(:source_import, SourceImport)

    field(:raid_slug, :string)
    field(:raid_name, :string)
    field(:encounter_id, :integer)
    field(:encounter_name, :string)

    field(:timeline_type, :string)
    field(:event_type, :string)
    field(:spell_id, :integer)
    field(:boss_only, :boolean)
    field(:comment, :string)

    field(:inference_tags, {:array, :string}, default: [])
    field(:inferred_mechanic_type, :string)
    field(:confidence, :string, default: "low")
    field(:review_status, :string, default: "inferred")

    field(:repository_revision, :string)
    field(:repository_license, :string)
    field(:source_file, :string)
    field(:source_line, :integer)
    field(:source_line_text, :string)
    field(:raw_entry, :map, default: %{})

    field(:product, :string, default: "wow")
    field(:channel, :string, default: "retail")
    field(:build_version, :string)
    field(:build_key, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :source_import_id,
      :raid_slug,
      :raid_name,
      :encounter_id,
      :encounter_name,
      :timeline_type,
      :event_type,
      :spell_id,
      :boss_only,
      :comment,
      :inference_tags,
      :inferred_mechanic_type,
      :confidence,
      :review_status,
      :repository_revision,
      :repository_license,
      :source_file,
      :source_line,
      :source_line_text,
      :raw_entry,
      :product,
      :channel,
      :build_version,
      :build_key
    ])
    |> validate_required([
      :source_import_id,
      :raid_slug,
      :encounter_id,
      :encounter_name,
      :timeline_type,
      :event_type,
      :spell_id,
      :inference_tags,
      :confidence,
      :review_status,
      :repository_revision,
      :repository_license,
      :source_file,
      :source_line,
      :source_line_text,
      :raw_entry,
      :product,
      :channel
    ])
    |> validate_inclusion(:timeline_type, @timeline_types)
    |> validate_inclusion(:confidence, @confidence_levels)
    |> validate_inclusion(:review_status, @review_statuses)
    |> foreign_key_constraint(:source_import_id)
    |> unique_constraint([:source_import_id, :source_line, :timeline_type, :spell_id],
      name: :wowanalyzer_timeline_candidate_source_line_index
    )
  end

  def timeline_types, do: @timeline_types
  def confidence_levels, do: @confidence_levels
  def review_statuses, do: @review_statuses
end
