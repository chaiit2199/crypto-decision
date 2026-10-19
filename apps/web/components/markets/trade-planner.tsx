"use client";

import { useState } from "react";
import type { FormEvent } from "react";

import type { PlanInput, TradePlan, TradingResult } from "@/lib/api/trading-types";
import { formatDecimal } from "@/lib/format/market";

type TradePlannerProps = {
    symbol: string;
    exchange: string;
    quoteAsset: string;
    suggestedPlan: TradePlan | null;
};

const FIELDS: { key: keyof PlanInput; label: string; hint: string }[] = [
    { key: "equity", label: "Vốn", hint: "Vốn giả định theo đồng định giá của cặp đang chọn." },
    { key: "risk_percent", label: "Rủi ro / lệnh (%)", hint: "Phần vốn tối đa chịu mất trong mô phỏng, gồm chi phí." },
    { key: "entry", label: "Giá vào", hint: "Giá mua giả định, không phải một lệnh đã khớp." },
    { key: "stop_loss", label: "Dừng lỗ", hint: "Mức giá vô hiệu hóa kế hoạch, thấp hơn giá vào." },
    { key: "take_profit", label: "Chốt lời", hint: "Mức thoát mục tiêu, cao hơn giá vào." },
    { key: "fee_percent", label: "Phí mỗi chiều (%)", hint: "Nhập theo biểu phí tài khoản thực tế; mặc định chỉ là giả định." },
    { key: "slippage_percent", label: "Trượt giá mỗi chiều (%)", hint: "Giả định chi phí spread và khớp lệch giá ở mỗi chiều." },
];

export function PlanSummary({ plan, quoteAsset }: { plan: TradePlan; quoteAsset: string }) {
    return (
        <dl className="trading-workbench__metrics">
            <div>
                <dt>Giá trị vị thế / {quoteAsset}</dt>
                <dd>{formatDecimal(plan.notional)}</dd>
            </div>
            <div>
                <dt>Ngân sách rủi ro / {quoteAsset}</dt>
                <dd>{formatDecimal(plan.risk_budget)}</dd>
            </div>
            <div>
                <dt>Lỗ tại SL sau chi phí / {quoteAsset}</dt>
                <dd>{formatDecimal(plan.net_loss)}</dd>
            </div>
            <div>
                <dt>Lãi tại TP sau chi phí / {quoteAsset}</dt>
                <dd>{formatDecimal(plan.net_profit)}</dd>
            </div>
            <div>
                <dt>R:R sau chi phí</dt>
                <dd>1 : {formatDecimal(plan.risk_reward_ratio)}</dd>
            </div>
            <div>
                <dt>Tổng chi phí giả định (%)</dt>
                <dd>{formatDecimal(plan.estimated_total_cost_pct)}</dd>
            </div>
        </dl>
    );
}

export function TradePlanner({ symbol, exchange, quoteAsset, suggestedPlan }: TradePlannerProps) {
    const [input, setInput] = useState<PlanInput>({
        equity: "1000",
        risk_percent: "0.5",
        entry: "",
        stop_loss: "",
        take_profit: "",
        fee_percent: "0.1",
        slippage_percent: "0.05",
    });
    const [result, setResult] = useState<TradingResult<TradePlan> | null>(null);
    const [isCalculating, setIsCalculating] = useState(false);

    function handleUseScenario() {
        if (!suggestedPlan) {
            return;
        }
        setInput({
            equity: suggestedPlan.equity,
            risk_percent: suggestedPlan.risk_percent,
            entry: suggestedPlan.entry,
            stop_loss: suggestedPlan.stop_loss,
            take_profit: suggestedPlan.take_profit,
            fee_percent: suggestedPlan.fee_percent,
            slippage_percent: suggestedPlan.slippage_percent,
        });
        setResult(null);
    }

    async function handleSubmit(event: FormEvent<HTMLFormElement>) {
        event.preventDefault();
        setIsCalculating(true);
        setResult(null);
        try {
            const response = await fetch("/api/trading", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ ...input, symbol, exchange }),
                signal: AbortSignal.timeout(10_000),
            });
            setResult(await response.json() as TradingResult<TradePlan>);
        } catch {
            setResult({ ok: false, message: "Không tính được mô phỏng. Vui lòng thử lại." });
        } finally {
            setIsCalculating(false);
        }
    }

    return (
        <section className="trading-workbench__planner" aria-label="Mô phỏng quản trị lệnh">
            <h3>Mô phỏng quản trị lệnh · {symbol} / {exchange}</h3>
            <p>Spot không đòn bẩy · Phí và trượt giá tính hai chiều trên giá trị vị thế ban đầu.</p>
            <form onSubmit={handleSubmit}>
                <fieldset disabled={isCalculating}>
                    <legend className="sr-only">Thông số mô phỏng</legend>
                    <div className="trading-workbench__form">
                        {FIELDS.map(({ key, label, hint }) => (
                            <label key={key}>
                                <span>{label}</span>
                                <input
                                    name={key}
                                    inputMode="decimal"
                                    required
                                    maxLength={72}
                                    value={input[key]}
                                    onChange={(event) => {
                                        setInput({ ...input, [key]: event.target.value });
                                        setResult(null);
                                    }}
                                />
                                <small>{hint}</small>
                            </label>
                        ))}
                    </div>
                    <div className="trading-workbench__actions">
                        <button type="submit">{isCalculating ? "Đang tính…" : "Tính mô phỏng"}</button>
                        {suggestedPlan && (
                            <button type="button" onClick={handleUseScenario}>Điền kịch bản ATR tham khảo</button>
                        )}
                    </div>
                </fieldset>
            </form>
            {result && !result.ok && <p role="alert">{result.message}</p>}
            {result?.ok && <PlanSummary plan={result.data} quoteAsset={quoteAsset} />}
            <p>Lỗ thực tế có thể vượt mô phỏng khi giá nhảy qua dừng lỗ hoặc không đủ thanh khoản.</p>
        </section>
    );
}
