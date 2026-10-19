"use client";

import { useState } from "react";
import type { FormEvent } from "react";

import type { PlanInput, TradePlan, TradingResult } from "@/lib/api/trading-types";
import { formatIndicator } from "@/lib/format/market";

type TradePlannerProps = {
    symbol: string;
    exchange: string;
    quoteAsset: string;
    currentPrice: string | null;
    suggestedPlan: TradePlan | null;
};

type PlannerFieldProps = {
    name: keyof PlanInput;
    label: string;
    unit: string;
    value: string;
    onChange: (name: keyof PlanInput, value: string) => void;
};

function PlannerField({ name, label, unit, value, onChange }: PlannerFieldProps) {
    return (
        <label className="trade-planner__field">
            <span>{label} <small>{unit}</small></span>
            <input
                name={name}
                inputMode="decimal"
                required
                maxLength={72}
                placeholder="Nhập giá trị"
                value={value}
                onChange={(event) => onChange(name, event.target.value)}
            />
        </label>
    );
}

export function PlanSummary({ plan, quoteAsset }: { plan: TradePlan; quoteAsset: string }) {
    return (
        <div className="trade-planner__result" role="status">
            <h4>Kết quả mô phỏng</h4>
            <dl className="trading-workbench__metrics">
                <div>
                    <dt>Giá trị mua · {quoteAsset}</dt>
                    <dd title={plan.notional}>{formatIndicator(plan.notional)}</dd>
                </div>
                <div>
                    <dt>Lỗ tại dừng lỗ · {quoteAsset}</dt>
                    <dd title={plan.net_loss}>{formatIndicator(plan.net_loss)}</dd>
                </div>
                <div>
                    <dt>Lãi tại chốt lời · {quoteAsset}</dt>
                    <dd title={plan.net_profit}>{formatIndicator(plan.net_profit)}</dd>
                </div>
                <div>
                    <dt>Tỷ lệ lỗ : lãi</dt>
                    <dd>1 : {formatIndicator(plan.risk_reward_ratio)}</dd>
                </div>
            </dl>
            <p>Đã tính phí và trượt giá hai chiều theo giả định đã nhập.</p>
            <details className="trading-workbench__frame">
                <summary>Chi tiết cách tính</summary>
                <dl className="trading-workbench__metrics">
                    <div>
                        <dt>Số lượng tài sản mua</dt>
                        <dd title={plan.quantity}>{formatIndicator(plan.quantity)}</dd>
                    </div>
                    <div>
                        <dt>Ngân sách rủi ro · {quoteAsset}</dt>
                        <dd>{formatIndicator(plan.risk_budget)}</dd>
                    </div>
                    <div>
                        <dt>Tổng chi phí giả định · {quoteAsset}</dt>
                        <dd>{formatIndicator(plan.estimated_cost)}</dd>
                        <dd>{formatIndicator(plan.estimated_total_cost_pct)}% giá trị mua ban đầu.</dd>
                    </div>
                </dl>
                <p>Phí và trượt giá hai chiều tính trên giá trị mua ban đầu, theo mô hình vốn cố định.</p>
            </details>
        </div>
    );
}

export function TradePlanner({ symbol, exchange, quoteAsset, currentPrice, suggestedPlan }: TradePlannerProps) {
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

    function handleChange(name: keyof PlanInput, value: string) {
        setInput((previous) => ({ ...previous, [name]: value }));
        setResult(null);
    }

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
        <section className="trade-planner" aria-label="Mô phỏng quản trị lệnh">
            <header className="trading-workbench__header">
                <div>
                    <h3>Tính vốn cho lệnh mua</h3>
                    <p>Nhập mức giá dự kiến để xem số vốn mua, khoản lỗ và lãi sau phí.</p>
                </div>
                <span className="trade-planner__identity">{symbol} · {exchange.toUpperCase()}</span>
            </header>
            <form onSubmit={handleSubmit}>
                <fieldset disabled={isCalculating}>
                    <legend className="sr-only">Thông số mô phỏng</legend>
                    <fieldset className="trade-planner__group">
                        <legend>1. Vốn & rủi ro</legend>
                        <div className="trade-planner__capital">
                            <PlannerField
                                name="equity"
                                label="Vốn dùng để mô phỏng"
                                unit={quoteAsset}
                                value={input.equity}
                                onChange={handleChange}
                            />
                            <PlannerField
                                name="risk_percent"
                                label="Rủi ro mỗi lệnh"
                                unit="% vốn"
                                value={input.risk_percent}
                                onChange={handleChange}
                            />
                        </div>
                        <p>Rủi ro là phần vốn chấp nhận mất nếu giá chạm dừng lỗ, đã gồm chi phí.</p>
                    </fieldset>
                    <fieldset className="trade-planner__group">
                        <legend>2. Giá dự kiến</legend>
                        <div className="trade-planner__prices">
                            <PlannerField
                                name="entry"
                                label="Giá vào"
                                unit={quoteAsset}
                                value={input.entry}
                                onChange={handleChange}
                            />
                            <PlannerField
                                name="stop_loss"
                                label="Dừng lỗ"
                                unit={quoteAsset}
                                value={input.stop_loss}
                                onChange={handleChange}
                            />
                            <PlannerField
                                name="take_profit"
                                label="Chốt lời"
                                unit={quoteAsset}
                                value={input.take_profit}
                                onChange={handleChange}
                            />
                        </div>
                        <p>Dừng lỗ thấp hơn giá vào; chốt lời cao hơn giá vào.</p>
                        {currentPrice && (
                            <button type="button" onClick={() => handleChange("entry", currentPrice)}>
                                Dùng giá hiện tại: {formatIndicator(currentPrice)} {quoteAsset}
                            </button>
                        )}
                    </fieldset>
                    <details
                        className="trading-workbench__frame"
                        onInvalidCapture={(event) => {
                            event.currentTarget.open = true;
                        }}
                    >
                        <summary>
                            Phí & trượt giá · {input.fee_percent || "—"}% + {input.slippage_percent || "—"}% mỗi chiều
                        </summary>
                        <p>Giá trị mặc định chỉ là giả định. Điều chỉnh theo biểu phí tài khoản và thanh khoản.</p>
                        <div className="trade-planner__capital">
                            <PlannerField
                                name="fee_percent"
                                label="Phí mỗi chiều"
                                unit="%"
                                value={input.fee_percent}
                                onChange={handleChange}
                            />
                            <PlannerField
                                name="slippage_percent"
                                label="Trượt giá mỗi chiều"
                                unit="%"
                                value={input.slippage_percent}
                                onChange={handleChange}
                            />
                        </div>
                    </details>
                    <div className="trading-workbench__actions">
                        <button type="submit" className="trade-planner__submit">
                            {isCalculating ? "Đang tính…" : "Tính mô phỏng"}
                        </button>
                        {suggestedPlan && (
                            <button type="button" onClick={handleUseScenario}>Điền kịch bản ATR tham khảo</button>
                        )}
                    </div>
                </fieldset>
            </form>
            {result && !result.ok && <p className="trading-workbench__status" role="alert">{result.message}</p>}
            {result?.ok && <PlanSummary plan={result.data} quoteAsset={quoteAsset} />}
            <p>Chỉ mô phỏng mua Spot, không đặt lệnh. Lỗ thực tế có thể lớn hơn khi giá nhảy hoặc thiếu thanh khoản.</p>
        </section>
    );
}
