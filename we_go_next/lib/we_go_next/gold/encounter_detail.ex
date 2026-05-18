defmodule WeGoNext.Gold.EncounterDetail do
  @moduledoc """
  Medallion encounter detail read model keyed by `gold.dim_encounter.id`.

  This module must not call legacy analyzers, analyzer JSON cache output, or
  `public.mechanic_criteria`.
  """

  import Ecto.Query

  alias WeGoNext.Gold.{DimEncounter, FactFailure}
  alias WeGoNext.Repo

  alias WeGoNext.Silver.{
    DamageDone,
    DamageTaken,
    DamageTakenEvent,
    Death,
    DebuffApplication,
    InterruptOpportunity,
    PlayerInfo
  }

  @type t :: %{
          encounter: DimEncounter.t(),
          counts: %{atom() => non_neg_integer()}
        }

  @doc """
  Returns a compact encounter detail shell read model for a gold encounter ID.
  """
  @spec get(pos_integer() | String.t()) :: {:ok, t()} | {:error, :not_found | :invalid_id}
  def get(id) do
    with {:ok, id} <- parse_id(id),
         %DimEncounter{} = encounter <- Repo.get(DimEncounter, id) do
      {:ok, %{encounter: encounter, counts: counts(id)}}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :invalid_id}
    end
  end

  defp counts(encounter_dim_id) do
    %{
      damage_taken_groups: count(DamageTaken, encounter_dim_id),
      damage_taken_events: count(DamageTakenEvent, encounter_dim_id),
      damage_done_groups: count(DamageDone, encounter_dim_id),
      deaths: count(Death, encounter_dim_id),
      interrupt_opportunities: count(InterruptOpportunity, encounter_dim_id),
      debuff_applications: count(DebuffApplication, encounter_dim_id),
      players: count(PlayerInfo, encounter_dim_id),
      failure_facts: count(FactFailure, encounter_dim_id)
    }
  end

  defp count(schema, encounter_dim_id) do
    schema
    |> where([row], row.encounter_dim_id == ^encounter_dim_id)
    |> Repo.aggregate(:count)
  end

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, ""} when parsed_id > 0 -> {:ok, parsed_id}
      _ -> :error
    end
  end

  defp parse_id(_id), do: :error
end
