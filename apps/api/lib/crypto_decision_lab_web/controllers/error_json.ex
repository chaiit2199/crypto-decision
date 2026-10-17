defmodule CryptoDecisionLabWeb.ErrorJSON do
  @moduledoc false
  def render(template, _assigns) do
    status = template |> String.split(".") |> hd()

    %{
      error: %{
        code: "http_" <> status,
        message: Phoenix.Controller.status_message_from_template(template)
      }
    }
  end
end
