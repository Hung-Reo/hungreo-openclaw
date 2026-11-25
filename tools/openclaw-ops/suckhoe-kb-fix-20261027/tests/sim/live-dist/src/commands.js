function recordText(record) {
    const status = record.status === "pending" ? "chờ Hưng duyệt" : record.status === "approved" ? "đã duyệt" : "đã từ chối";
    return [
        "🩺 Suckhoe KB Weekly Candidate",
        `• Chủ đề: ${record.title}`,
        `• Tuần: ${record.weekOf}`,
        `• Tóm tắt: ${record.summary}`,
        `• Nguồn: ${record.sourceCount}`,
        `• Trạng thái: ${status}`,
        `• Drive: ${record.driveUrl}`,
    ].join("\n");
}
function friendlyError(error) {
    const code = error instanceof Error ? error.message : "unknown";
    if (code === "review_token_not_found")
        return "Không tìm thấy yêu cầu duyệt này.";
    if (code === "review_token_still_valid") return "Mã duyệt vẫn còn hiệu lực; không cần cấp lại.";
    if (code === "review_token_expired")
        return "Yêu cầu duyệt đã hết hạn; candidate vẫn chưa vào KB.";
    if (code.startsWith("review_already_"))
        return "Candidate này đã được xử lý trước đó.";
    if (code === "candidate_hash_changed")
        return "Candidate đã thay đổi sau khi stage nên hệ thống đã chặn duyệt.";
    if (code.startsWith("candidate_revalidation_failed"))
        return "Candidate không còn vượt qua validator nên chưa được đưa vào KB.";
    if (code === "review_decision_in_progress")
        return "Candidate đang được xử lý, thử lại sau vài giây.";
    return "Không thể xử lý candidate an toàn; chưa có thay đổi nào vào KB.";
}
export function createReviewCommand(config, store) {
    return {
        name: "kb-review",
        description: "Review a staged Suckhoe KB weekly candidate",
        acceptsArgs: true,
        requireAuth: true,
        handler: async (ctx) => {
            const senderId = String(ctx.senderId ?? "");
            if (!ctx.isAuthorizedSender || !config.allowedTelegramUserIds.includes(senderId)) {
                return { text: "Bạn không có quyền duyệt Suckhoe KB candidate." };
            }
            const [action, token, ...extra] = (ctx.args ?? "").trim().split(/\s+/).filter(Boolean);
            if (!action || !token || extra.length > 0 || !["show", "approve", "reject", "renew"].includes(action) || !/^[A-Za-z0-9_-]{16}$/.test(token)) {
                return { text: "Lệnh duyệt không hợp lệ." };
            }
            try {
                if (action === "show")
                    return { text: recordText(await store.show(token)) };
                if (action === "renew") {
                    const renewed = await store.renew(token, senderId, config.approvalTtlDays);
                    return { text: `${recordText(renewed)}\n\nĐã cấp mã duyệt mới; mã cũ không còn hiệu lực.`, presentation: reviewNotification(renewed).presentation };
                }
                const result = await store.decide(token, action, senderId);
                return {
                    text: action === "approve"
                        ? `✅ Đã duyệt và đưa ${result.candidateId} vào Suckhoe KB.`
                        : `❌ Đã từ chối ${result.candidateId}; KB approved không thay đổi.`,
                };
            }
            catch (error) {
                return { text: friendlyError(error) };
            }
        },
    };
}
export function reviewNotification(record) {
    return {
        text: `${recordText(record)}\n\nCandidate chỉ vào KB sau khi Hưng bấm Duyệt. Nút có hiệu lực 7 ngày.`,
        presentation: {
            blocks: [{
                    type: "buttons",
                    buttons: [
                        { label: "Xem file", url: record.driveUrl },
                        { label: "Duyệt", action: { type: "command", command: `/kb-review approve ${record.token}` }, style: "success" },
                        { label: "Từ chối", action: { type: "command", command: `/kb-review reject ${record.token}` }, style: "danger" },
                    ],
                }],
        },
    };
}
