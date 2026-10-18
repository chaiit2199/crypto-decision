defmodule CryptoDecisionLab.TradingKnowledge.LibraryTest do
  use CryptoDecisionLab.DataCase, async: true
  alias CryptoDecisionLab.TradingKnowledge
  alias CryptoDecisionLab.TradingKnowledge.{Canonical, Validator}

  defp example do
    TradingKnowledge.library_path()
    |> Path.join("ema_trend_continuation.v1.json")
    |> File.read!()
    |> Jason.decode!()
  end

  test "ten documented hypotheses import idempotently without success claims" do
    assert {:ok, versions} = TradingKnowledge.import_directory()
    assert length(versions) == 10
    assert {:ok, again} = TradingKnowledge.import_directory()
    assert Enum.map(again, & &1.id) == Enum.map(versions, & &1.id)

    for row <- versions do
      assert row.document["validation"]["status"] == "unvalidated"
      assert row.document["validation"]["evidence_ids"] == []
      assert row.content_hash == Canonical.hash(row.document)
    end
  end

  test "same version cannot change; a new version preserves history" do
    original = example()
    assert {:ok, first} = TradingKnowledge.import_document(original)

    assert {:error, :immutable_version_conflict} =
             TradingKnowledge.import_document(Map.put(original, "name", "Changed hypothesis"))

    assert {:ok, second} = TradingKnowledge.import_document(Map.put(original, "version", 2))
    assert [^first, ^second] = TradingKnowledge.history(original["strategy_id"])
  end

  test "schema rejects unknown keys, unsafe operators, malformed versions, decimals and dates" do
    original = example()

    for invalid <- [
          Map.put(original, "win_rate", "0.99"),
          Map.put(original, "schema_version", "2.0.0"),
          Map.put(original, "version", 0),
          put_in(original, ["risk_constraints", "stop_loss_fraction"], 0.02),
          put_in(original, ["risk_constraints", "stop_loss_fraction"], "NaN"),
          put_in(original, ["provenance", "created_at"], "2026-99-99T00:00:00Z"),
          Map.update!(original, "entry_conditions", fn [c | rest] ->
            [Map.put(c, "operator", "eval") | rest]
          end)
        ] do
      assert {:error, _} = Validator.validate(invalid)
    end
  end

  test "semantic checks reject self-certification, invalid risk, duplicate IDs and mixed units" do
    original = example()

    for invalid <- [
          put_in(original, ["validation", "status"], "validated"),
          put_in(original, ["validation", "evidence_ids"], [1]),
          put_in(original, ["risk_constraints", "stop_loss_fraction"], "0"),
          put_in(original, ["risk_constraints", "max_risk_fraction"], "1.1"),
          put_in(original, ["risk_constraints", "take_profit_fraction"], "0.01"),
          Map.put(original, "confirmation_conditions", original["entry_conditions"]),
          Map.update!(original, "entry_conditions", fn [c | rest] ->
            [put_in(c, ["right", "feature"], "rsi14") | rest]
          end)
        ] do
      assert {:error, _} = Validator.validate(invalid)
    end
  end

  test "duplicate JSON keys are rejected at every depth" do
    assert {:error, :duplicate_json_key} = TradingKnowledge.decode(~s({"a":{"x":1,"x":2}}))
    assert {:error, :duplicate_json_key} = TradingKnowledge.decode(~s({"a":[{"x":1,"x":2}]}))
  end

  test "canonical hashing ignores object order but retains array order" do
    assert Canonical.hash(%{"b" => 2, "a" => 1}) == Canonical.hash(%{"a" => 1, "b" => 2})
    refute Canonical.hash([1, 2]) == Canonical.hash([2, 1])
  end

  test "database rejects modification and deletion even outside the context" do
    {:ok, row} = TradingKnowledge.import_document(example())

    for sql <- [
          "UPDATE knowledge_strategy_versions SET version = 9 WHERE id = $1",
          "DELETE FROM knowledge_strategy_versions WHERE id = $1"
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
               Repo.query(sql, [row.id], mode: :savepoint)
    end

    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query("TRUNCATE knowledge_realized_outcomes", [], mode: :savepoint)
  end
end
