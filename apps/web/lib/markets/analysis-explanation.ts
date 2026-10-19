import type { MarketAnalysisData } from "@/lib/api/types";

export const SIGNAL_EXPLANATIONS: Record<MarketAnalysisData["signal"], string> = {
    BUY: "Xu hướng tăng, động lượng mua tích cực và biến động chưa tăng cao đang đồng thuận. Có thể theo dõi cơ hội mua, nhưng cần xác định điểm vào, mức dừng lỗ và giới hạn rủi ro trước khi quyết định.",
    SELL: "Xu hướng giảm và động lượng suy yếu đang đồng thuận. Nếu đang nắm giữ, nên đánh giá lại mức rủi ro và phương án giảm vị thế. Đây không phải lệnh bán tự động hoặc khuyến nghị mở short.",
    WAIT: "Các điều kiện chưa đủ đồng thuận hoặc mức biến động cần thận trọng. Theo dõi thêm nến đóng tiếp theo trước khi xem xét hành động.",
    NO_DATA: "Dữ liệu chưa đủ mới hoặc chưa đủ lịch sử để đưa ra nhận định có cơ sở.",
};

export const ANSWER_EXPLANATIONS: Record<string, string> = {
    BULLISH: "Cấu trúc giá và đường trung bình nghiêng về xu hướng tăng.",
    BEARISH: "Cấu trúc giá và đường trung bình nghiêng về xu hướng giảm.",
    SIDEWAYS: "Xu hướng chưa rõ; giá có thể đang dao động trong vùng hoặc các chỉ báo chưa đồng thuận.",
    STRENGTHENING: "RSI, biến động giá và vị trí giá hiện tại cho thấy động lượng mua tích cực.",
    WEAKENING: "Các yếu tố động lượng cho thấy sức mua suy yếu hoặc áp lực bán tăng.",
    MIXED: "Các chỉ báo động lượng đưa ra tín hiệu trái chiều.",
    ELEVATED: "Biên độ dao động đang cao; cần thận trọng với biến động bất lợi và kích thước vị thế.",
    NORMAL: "Dữ liệu quan sát chưa cho thấy biến động tăng cao; điều này không bảo đảm rủi ro thấp.",
    SCALP: "Cấu trúc quan sát nghiêng về giữ ngắn (vài phút). Không phải dự báo lãi scalp.",
    INTRADAY: "Cấu trúc quan sát nghiêng về giữ trong ngày. Không phải dự báo lãi intraday.",
    SWING: "Cấu trúc đa khung nghiêng về giữ nhiều ngày. Không phải khuyến nghị đầu tư dài hạn có lãi.",
    UNSUITABLE: "Thiếu dữ liệu, xung đột khung thời gian hoặc biến động cao — chưa phù hợp mở nghiên cứu giữ lệnh.",
};
