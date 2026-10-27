function requiredString(value, name) {
    if (typeof value !== "string" || !value.trim()) {
        throw new Error(`Missing plugin config: ${name}`);
    }
    return value.trim();
}
export function parseConfig(raw) {
    const value = (raw ?? {});
    const users = value.allowedTelegramUserIds;
    if (!Array.isArray(users) || users.length === 0 || users.some((item) => !/^\d+$/.test(String(item)))) {
        throw new Error("allowedTelegramUserIds must contain Telegram numeric user IDs");
    }
    const config = {
        kbRoot: requiredString(value.kbRoot, "kbRoot"),
        whitelistPath: requiredString(value.whitelistPath, "whitelistPath"),
        driveFolderId: requiredString(value.driveFolderId, "driveFolderId"),
        serviceAccountPath: requiredString(value.serviceAccountPath, "serviceAccountPath"),
        openclawBin: requiredString(value.openclawBin, "openclawBin"),
        openclawStateDir: requiredString(value.openclawStateDir, "openclawStateDir"),
        openclawConfigPath: requiredString(value.openclawConfigPath, "openclawConfigPath"),
        reviewChatId: requiredString(value.reviewChatId, "reviewChatId"),
        allowedTelegramUserIds: users.map(String),
        pollIntervalSeconds: Number(value.pollIntervalSeconds ?? 300),
        initialPollDelaySeconds: Number(value.initialPollDelaySeconds ?? 15),
        approvalTtlDays: Number(value.approvalTtlDays ?? 7),
        maxFileBytes: Number(value.maxFileBytes ?? 262_144),
    };
    if (!/^[A-Za-z0-9_-]{10,}$/.test(config.driveFolderId))
        throw new Error("driveFolderId is invalid");
    if (!Number.isInteger(config.pollIntervalSeconds) || config.pollIntervalSeconds < 60) {
        throw new Error("pollIntervalSeconds must be an integer >= 60");
    }
    if (!Number.isInteger(config.initialPollDelaySeconds) || config.initialPollDelaySeconds < 1 || config.initialPollDelaySeconds > 300) {
        throw new Error("initialPollDelaySeconds must be between 1 and 300");
    }
    if (!Number.isInteger(config.approvalTtlDays) || config.approvalTtlDays < 1 || config.approvalTtlDays > 30) {
        throw new Error("approvalTtlDays must be between 1 and 30");
    }
    if (!Number.isInteger(config.maxFileBytes) || config.maxFileBytes < 1024 || config.maxFileBytes > 1_048_576) {
        throw new Error("maxFileBytes must be between 1024 and 1048576");
    }
    return config;
}
