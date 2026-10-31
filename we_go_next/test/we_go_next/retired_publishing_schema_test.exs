defmodule WeGoNext.RetiredPublishingSchemaTest do
  use WeGoNext.DataCase, async: true

  alias WeGoNext.Repo

  test "migrated database drops publishing data but retains gold identity" do
    result =
      Ecto.Adapters.SQL.query!(Repo, """
      SELECT table_schema, table_name, column_name
      FROM information_schema.columns
      WHERE table_schema IN ('public', 'gold')
      """)

    columns = MapSet.new(result.rows)

    for table <- ["mirror_uploads", "public_reports"] do
      refute Enum.any?(columns, fn [schema, name, _] -> schema == "public" and name == table end)
    end

    refute ["public", "combat_log_files", "publish_enabled"] in columns

    for column <-
          ~w(document_r2_endpoint document_r2_bucket document_r2_access_key_id document_r2_secret_access_key_encrypted document_r2_secret_access_key_set_at) do
      refute ["public", "users", column] in columns
    end

    assert ["gold", "dim_encounter", "source_encounter_key"] in columns
    assert ["gold", "dim_mechanic_criterion", "criterion_key"] in columns
  end
end
