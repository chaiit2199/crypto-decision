defmodule CryptoDecisionLab.FixtureTransport do
  def get(path, params) do
    Process.put(:http_calls, Process.get(:http_calls, []) ++ [{path, params}])

    case Process.get(:http_responses, []) do
      [response | rest] ->
        Process.put(:http_responses, rest)
        if is_function(response, 2), do: response.(path, params), else: response

      [] ->
        raise "Unexpected HTTP request: #{path}"
    end
  end
end
