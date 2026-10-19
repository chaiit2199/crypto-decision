import "server-only";

import { z } from "zod";

import type { TradingResult } from "./trading-types";

export async function getTradingResult<T>(
    path: string,
    schema: z.ZodType<T>,
    body?: Record<string, string>,
): Promise<TradingResult<T>> {
    try {
        const response = await fetch(new URL(path, process.env.API_BASE_URL ?? "http://127.0.0.1:4000"), {
            method: body ? "POST" : "GET",
            headers: body ? { "Content-Type": "application/json" } : undefined,
            body: body ? JSON.stringify(body) : undefined,
            cache: "no-store",
            signal: AbortSignal.timeout(20_000),
        });
        if (!response.ok) {
            return {
                ok: false,
                message: response.status === 400
                    ? "Thông số không hợp lệ. Dùng số thập phân, rủi ro tối đa 5% và dừng lỗ < giá vào < chốt lời."
                    : "Không tải được dữ liệu nghiên cứu. Vui lòng thử lại.",
            };
        }
        const parsed = z.object({ data: schema }).safeParse(await response.json());
        if (!parsed.success) {
            return { ok: false, message: "Dữ liệu nghiên cứu không đúng định dạng." };
        }
        return { ok: true, data: parsed.data.data };
    } catch {
        return { ok: false, message: "Mất kết nối API nghiên cứu. Vui lòng thử lại." };
    }
}
