defmodule WeGoNext.SourceData.DbmMechanicCandidate do
  @moduledoc """
  Mechanic candidate inferred from a DBM module warning.

  Candidates are source evidence. They are not active mechanic rules and do not
  directly produce gold facts until a later review/promotion workflow turns them
  into `rules.mechanic_criterion` rows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias WeGoNext.SourceData.SourceImport

  @schema_prefix "source_data"
  @confidence_levels ~w(high medium low)
  @review_statuses ~w(inferred accepted rejected ignored overridden)

  schema "dbm_mechanic_candidate" do
    belongs_to(:source_import, SourceImport)

    field(:module_addon, :string)
    field(:module_id, :integer)
    field(:module_map_id, :integer)
    field(:module_revision, :string)
    field(:encounter_id, :integer)
    field(:zone_id, :integer)
    field(:creature_ids, {:array, :integer}, default: [])

    field(:warning_var, :string)
    field(:warning_constructor, :string)
    field(:spell_id, :integer)
    field(:role_filter, :string)
    field(:label_tokens, {:array, :string}, default: [])
    field(:alert_tokens, {:array, :string}, default: [])
    field(:inference_tags, {:array, :string}, default: [])
    field(:inferred_mechanic_type, :string)
    field(:confidence, :string, default: "low")
    field(:review_status, :string, default: "inferred")

    field(:source_file, :string)
    field(:source_line, :integer)
    field(:source_line_text, :string)
    field(:raw_args, :string)
    field(:comment, :string)

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
      :module_addon,
      :module_id,
      :module_map_id,
      :module_revision,
      :encounter_id,
      :zone_id,
      :creature_ids,
      :warning_var,
      :warning_constructor,
      :spell_id,
      :role_filter,
      :label_tokens,
      :alert_tokens,
      :inference_tags,
      :inferred_mechanic_type,
      :confidence,
      :review_status,
      :source_file,
      :source_line,
      :source_line_text,
      :raw_args,
      :comment,
      :product,
      :channel,
      :build_version,
      :build_key
    ])
    |> validate_required([
      :source_import_id,
      :creature_ids,
      :warning_var,
      :warning_constructor,
      :spell_id,
      :label_tokens,
      :alert_tokens,
      :inference_tags,
      :confidence,
      :review_status,
      :source_file,
      :source_line,
      :source_line_text,
      :raw_args,
      :product,
      :channel
    ])
    |> validate_inclusion(:confidence, @confidence_levels)
    |> validate_inclusion(:review_status, @review_statuses)
    |> foreign_key_constraint(:source_import_id)
    |> unique_constraint([:source_import_id, :source_line, :warning_var],
      name: :dbm_mechanic_candidate_source_line_index
    )
  end

  def confidence_levels, do: @confidence_levels
  def review_statuses, do: @review_statuses
end
