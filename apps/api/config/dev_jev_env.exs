# Read only local Jev assignments; never evaluate shell expressions or log values.
fn path ->
  case File.read(path) do
    {:error, :enoent} ->
      %{}

    {:error, _reason} ->
      raise "Cannot read JEV_ENV_FILE"

    {:ok, contents} ->
      contents
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {line, number}, values ->
        line = String.trim(line)

        if line == "" or String.starts_with?(line, "#") do
          values
        else
          pattern =
            ~r/^(?:export\s+)?(?<key>JEV_ENABLED|TYPESAFE_API_KEY|JEV_MODEL)\s*=\s*(?:"(?<double>[^"]*)"|'(?<single>[^']*)'|(?<bare>[^\s#"'$`]*))(?:\s+#.*)?$/

          case Regex.named_captures(pattern, line) do
            nil ->
              raise "Invalid Jev assignment in JEV_ENV_FILE at line #{number}"

            captures ->
              value =
                Enum.find(
                  [captures["double"], captures["single"], captures["bare"]],
                  "",
                  &(&1 != "")
                )

              Map.put(values, captures["key"], value)
          end
        end
      end)
  end
end
