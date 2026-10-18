defmodule CryptoDecisionLab.TradingKnowledge.Schema do
  @moduledoc "Validator for the closed JSON Schema vocabulary used by strategy v1, not a general schema engine."
  @path Path.expand("../../../priv/knowledge/strategy.schema.json", __DIR__)
  @external_resource @path
  @schema @path |> File.read!() |> Jason.decode!()
  @keywords ~w($schema $id title type properties required additionalProperties oneOf const enum items minItems maxItems uniqueItems minLength maxLength pattern format minimum maximum)

  @spec validate(term()) :: :ok | {:error, list()}
  def validate(value) do
    case errors(value, @schema, "$") do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp errors(value, schema, path) do
    unknown = Map.keys(schema) -- @keywords

    cond do
      unknown != [] ->
        [{path, :unsupported_schema_keyword}]

      Map.has_key?(schema, "oneOf") ->
        if Enum.count(schema["oneOf"], &(errors(value, &1, path) == [])) == 1,
          do: [],
          else: [{path, :one_of}]

      not type?(value, schema["type"]) ->
        [{path, :type}]

      true ->
        checks(value, schema, path) ++ children(value, schema, path)
    end
  end

  defp type?(v, "object"), do: is_map(v) and not is_struct(v)
  defp type?(v, "array"), do: is_list(v)
  defp type?(v, "string"), do: is_binary(v)
  defp type?(v, "integer"), do: is_integer(v)
  defp type?(_, _), do: false

  defp checks(v, s, p) do
    Enum.flat_map(s, fn {key, expected} ->
      valid =
        case key do
          "const" -> v == expected
          "enum" -> v in expected
          "minLength" -> String.length(v) >= expected
          "maxLength" -> String.length(v) <= expected
          "pattern" -> Regex.match?(Regex.compile!(expected), v)
          "format" -> expected == "date-time" and match?({:ok, _, 0}, DateTime.from_iso8601(v))
          "minimum" -> v >= expected
          "maximum" -> v <= expected
          "minItems" -> length(v) >= expected
          "maxItems" -> length(v) <= expected
          "uniqueItems" -> not expected or length(v) == length(Enum.uniq(v))
          _ -> true
        end

      if valid, do: [], else: [{p, key}]
    end)
  end

  defp children(v, %{"type" => "object"} = s, p) do
    properties = s["properties"]
    missing = Enum.map(s["required"] -- Map.keys(v), &{p <> "." <> &1, :required})
    extra = Enum.map(Map.keys(v) -- Map.keys(properties), &{p <> "." <> to_string(&1), :unknown})

    nested =
      Enum.flat_map(properties, fn {key, child} ->
        if Map.has_key?(v, key), do: errors(v[key], child, p <> "." <> key), else: []
      end)

    missing ++ extra ++ nested
  end

  defp children(v, %{"type" => "array"} = s, p) do
    v
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, i} -> errors(item, s["items"], "#{p}[#{i}]") end)
  end

  defp children(_, _, _), do: []
end
