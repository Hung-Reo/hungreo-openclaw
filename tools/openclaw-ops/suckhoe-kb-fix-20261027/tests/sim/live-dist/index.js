import { access } from "node:fs/promises";
import { loadWhitelist } from "./src/candidate.js";
import { createReviewCommand, reviewNotification } from "./src/commands.js";
import { parseConfig } from "./src/config.js";
import { ServiceAccountDriveReader } from "./src/drive.js";
import { CandidatePoller } from "./src/poller.js";
import { ReviewStore } from "./src/store.js";
import { sendTelegramViaCli } from "./src/telegram-delivery.js";
export default function register(api) {
    const config = parseConfig(api.pluginConfig);
    let timer = null;
    let initialTimer = null;
    let running = false;
    let poller = null;
    let store = null;
    async function initialize() {
        if (store && poller)
            return { store, poller };
        const whitelist = await loadWhitelist(config.whitelistPath);
        store = new ReviewStore(config.kbRoot, whitelist, config.maxFileBytes);
        await store.initialize();
        const drive = new ServiceAccountDriveReader(config.serviceAccountPath);
        poller = new CandidatePoller(config, whitelist, store, drive, {
            candidate: async (record) => {
                const message = reviewNotification(record);
                await sendTelegramViaCli(config, message.text, message.presentation);
            },
            noChange: async (file, summary) => {
                await sendTelegramViaCli(config, `ℹ️ Suckhoe KB Weekly: tuần này Claude đề xuất không thêm candidate.\n• ${summary}\n• Drive: ${file.webViewLink ?? `https://drive.google.com/file/d/${file.id}/view`}`);
            },
            invalid: async (file, reason) => {
                await sendTelegramViaCli(config, `⚠️ Suckhoe KB Weekly candidate chưa đạt cổng kiểm tra và chưa vào KB.\n• Lý do: ${reason}\n• File: ${file.webViewLink ?? file.name}`);
            },
        });
        return { store, poller };
    }
    api.registerCommand({
        name: "kb-review",
        description: "Review a staged Suckhoe KB weekly candidate",
        acceptsArgs: true,
        requireAuth: true,
        handler: async (ctx) => {
            const initialized = await initialize();
            return createReviewCommand(config, initialized.store).handler(ctx);
        },
    });
    api.registerService({
        id: "suckhoe-kb-weekly-drive-poller",
        start: async () => {
            try {
                await access(config.serviceAccountPath);
            }
            catch {
                api.logger.warn(`Drive polling disabled until service account exists at ${config.serviceAccountPath}`);
                return;
            }
            const initialized = await initialize();
            const run = async () => {
                if (running)
                    return;
                running = true;
                try {
                    const result = await initialized.poller.pollOnce();
                    if (result.checked > 0)
                        api.logger.info(`Drive poll checked=${result.checked} imported=${result.imported}`);
                }
                catch (error) {
                    api.logger.error(`Drive poll failed: ${error instanceof Error ? error.message : "unknown"}`);
                }
                finally {
                    running = false;
                }
            };
            initialTimer = setTimeout(() => void run(), config.initialPollDelaySeconds * 1000);
            initialTimer.unref();
            timer = setInterval(() => void run(), config.pollIntervalSeconds * 1000);
            timer.unref();
        },
        stop: () => {
            if (timer)
                clearInterval(timer);
            if (initialTimer)
                clearTimeout(initialTimer);
            timer = null;
            initialTimer = null;
        },
    });
}
