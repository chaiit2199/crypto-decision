defmodule CryptoDecisionLabWeb.ErrorJSONTest do
  use ExUnit.Case, async: true
  alias CryptoDecisionLabWeb.ErrorJSON

  test "unexpected errors have the same safe error envelope" do
    assert ErrorJSON.render("500.json", %{}) == %{
             error: %{code: "http_500", message: "Internal Server Error"}
           }

    assert ErrorJSON.render("404.json", %{}) == %{
             error: %{code: "http_404", message: "Not Found"}
           }
  end
end
