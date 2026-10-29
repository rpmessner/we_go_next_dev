defmodule WeGoNext.Analysis.Result do
  @moduledoc "Bounded Tool envelopes. Cursors bind an offset to Tool, session and filter args."
  @cap 8_192
  def cap, do: @cap

  def page(rows, args, scope, render \\ &Function.identity/1, cap \\ @cap) do
    fingerprint =
      :crypto.hash(:sha256, :erlang.term_to_binary({scope, Map.delete(args, "cursor")}))
      |> Base.url_encode64(padding: false)

    with {:ok, offset} <- offset(args["cursor"], fingerprint) do
      remaining = Enum.drop(rows, offset)
      fit(remaining, [], offset, fingerprint, render, cap)
    end
  end

  defp offset(nil, _fingerprint), do: {:ok, 0}

  defp offset(cursor, fingerprint) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"offset" => n, "scope" => ^fingerprint}} <- Jason.decode(json),
         true <- is_integer(n) and n >= 0 do
      {:ok, n}
    else
      _ -> {:error, "Invalid cursor for this Tool, session or filters"}
    end
  end

  defp offset(_, _), do: {:error, "Invalid cursor"}

  defp fit([], accepted, _offset, _fingerprint, render, cap) do
    finish(accepted, render, false, nil, cap)
  end

  defp fit([row | rest], accepted, offset, fingerprint, render, cap) do
    candidate = accepted ++ [row]
    cursor = cursor(offset + length(candidate), fingerprint)
    envelope = envelope(candidate, render, rest != [], if(rest == [], do: nil, else: cursor))

    if byte_size(Jason.encode!(envelope)) <= cap do
      fit(rest, candidate, offset, fingerprint, render, cap)
    else
      case accepted do
        [] -> {:error, "A single result row exceeds the Tool result cap"}
        _ -> finish(accepted, render, true, cursor(offset + length(accepted), fingerprint), cap)
      end
    end
  end

  defp finish(rows, render, truncated, cursor, cap) do
    result = envelope(rows, render, truncated, cursor)

    if byte_size(Jason.encode!(result)) <= cap,
      do: {:ok, result},
      else: {:error, "Result metadata exceeds the Tool result cap"}
  end

  defp envelope(rows, render, truncated, cursor) do
    %{
      data: render.(Enum.map(rows, &elem(&1, 0))),
      evidence: Enum.map(rows, &elem(&1, 1)),
      truncated: truncated,
      next_cursor: cursor
    }
  end

  defp cursor(offset, fingerprint),
    do: Base.url_encode64(Jason.encode!(%{offset: offset, scope: fingerprint}), padding: false)
end
