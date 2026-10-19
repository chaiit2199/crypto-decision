import type { MarketAnalysisData } from "@/lib/api/types";

export const SIGNAL_EXPLANATIONS: Record<MarketAnalysisData["signal"], string> =
    {
        BUY: "Xu hướng tăng và động lượng mua đang đồng thuận, biến động chưa tăng cao. Có thể theo dõi cơ hội mua; vẫn cần tự chọn điểm vào, dừng lỗ và mức rủi ro.",
        SELL: "Xu hướng giảm và động lượng suy yếu đang đồng thuận. Nếu đang nắm giữ, nên xem lại rủi ro và phương án giảm vị thế. Không phải lệnh bán tự động.",
        WAIT: "Điều kiện chưa đủ đồng thuận hoặc biến động cần thận trọng. Nên chờ nến đóng tiếp theo trước khi hành động.",
        NO_DATA:
            "Dữ liệu chưa đủ mới hoặc chưa đủ lịch sử để đưa ra nhận định.",
    };

export const ANSWER_EXPLANATIONS: Record<string, string> = {
    BULLISH: "Giá và đường trung bình nghiêng về xu hướng tăng.",
    BEARISH: "Giá và đường trung bình nghiêng về xu hướng giảm.",
    SIDEWAYS:
        "Xu hướng chưa rõ; giá có thể đang dao động hoặc các chỉ báo chưa đồng thuận.",
    STRENGTHENING: "Động lượng mua đang tích cực.",
    WEAKENING: "Sức mua suy yếu hoặc áp lực bán tăng.",
    MIXED: "Các chỉ báo động lượng trái chiều.",
    ELEVATED: "Biên độ dao động đang cao; cần thận trọng với kích thước vị thế.",
    NORMAL: "Chưa thấy biến động tăng cao; điều này không bảo đảm rủi ro thấp.",
    SCALP: "Cấu trúc quan sát nghiêng về giữ vài phút.",
    INTRADAY: "Cấu trúc quan sát nghiêng về giữ trong ngày.",
    SWING: "Cấu trúc đa khung nghiêng về giữ nhiều ngày.",
    UNSUITABLE:
        "Thiếu dữ liệu, xung đột khung giờ hoặc biến động cao — chưa phù hợp giữ lệnh.",
};
