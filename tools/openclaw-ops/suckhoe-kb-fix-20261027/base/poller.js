import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { validateCandidate } from "./candidate.js";
export function friendlyValidationReason(errors) {
    const reasons = [];
    const add = (reason) => {
        if (!reasons.includes(reason))
            reasons.push(reason);
    };
    if (errors.some((error) => error.includes("source_domain_not_allowed"))) {
        add("có nguồn ngoài consumer-health whitelist");
    }
    if (errors.includes("sources_count_invalid")) {
        add("candidate quá rộng; chỉ được dùng tối đa 6 nguồn");
    }
    if (errors.some((error) => error.startsWith("unsafe_universal_") || error.startsWith("unsafe_oral_"))) {
        add("có hướng dẫn y tế áp dụng chung hoặc không an toàn");
    }
    if (errors.some((error) => error.includes("unsafe_or_personal_content"))) {
        add("có nội dung cá nhân hoặc chỉ dẫn không an toàn");
    }
    if (errors.some((error) => error.includes("claim_source"))) {
        add("claim chưa map đủ về nguồn");
    }
    if (errors.includes("topic_rotation_mismatch")) {
        add("topic không khớp vòng tuần");
    }
    if (errors.includes("candidate_id_metadata_mismatch")) {
        add("candidate_id không khớp week_of/topic");
    }
    const missingHeadings = errors
        .filter((error) => error.startsWith("heading_missing:"))
        .map((error) => error.slice("heading_missing:".length));
    if (missingHeadings.length > 0) {
        add(`thiếu section bắt buộc: ${missingHeadings.join(", ")}`);
    }
    if (errors.includes("candidate_missing_header")) {
        add("thiếu header candidate bắt buộc");
    }
    if (errors.includes("candidate_missing_footer")) {
        add("metadata candidate chưa đóng đúng định dạng");
    }
    return reasons.length > 0 ? reasons.join("; ") : "thiếu cấu trúc hoặc metadata bắt buộc";
}
export class CandidatePoller {
    config;
    whitelist;
    store;
    drive;
    notifier;
    indexPath;
    constructor(config, whitelist, store, drive, notifier) {
        this.config = config;
        this.whitelist = whitelist;
        this.store = store;
        this.drive = drive;
        this.notifier = notifier;
        this.indexPath = path.join(config.kbRoot, "medical", "review-state", "drive-files.json");
    }
    async readIndex() {
        try {
            return JSON.parse(await readFile(this.indexPath, "utf8"));
        }
        catch {
            return {};
        }
    }
    async writeIndex(index) {
        await mkdir(path.dirname(this.indexPath), { recursive: true });
        const temp = `${this.indexPath}.${process.pid}.tmp`;
        await writeFile(temp, `${JSON.stringify(index, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
        await rename(temp, this.indexPath);
    }
    async retryCandidateNotification(file, entry, index) {
        const record = (await this.store.listRecords()).find((item) => item.candidateId === entry.candidateId && item.driveFileId === file.id);
        if (!record || record.status !== "pending") {
            entry.notificationPending = false;
            await this.writeIndex(index);
            return;
        }
        entry.lastNotificationAttemptAt = new Date().toISOString();
        try {
            await this.notifier.candidate(record);
            entry.notificationPending = false;
            entry.notifiedAt = new Date().toISOString();
        }
        catch {
            entry.notificationPending = true;
        }
        await this.writeIndex(index);
    }
    async pollOnce() {
        await this.store.initialize();
        const index = await this.readIndex();
        const files = await this.drive.listFiles(this.config.driveFolderId);
        let checked = 0;
        let imported = 0;
        for (const file of files) {
            const seen = index[file.id];
            if (seen) {
                if (seen.status === "imported" && seen.notificationPending) {
                    await this.retryCandidateNotification(file, seen, index);
                }
                if (!seen.modifiedTime) {
                    seen.modifiedTime = file.modifiedTime;
                    continue;
                }
                if (!file.modifiedTime || seen.modifiedTime === file.modifiedTime)
                    continue;
            }
            // Chi xu ly candidate that: ten phai bat dau "suckhoe-".
            // Bo qua HOAN TOAN file khac (vd _review-status.md do VPS ghi nguoc len Inbox)
            // -> khong doc, khong danh invalid, khong ban notification rac. (2026-08-18)
            if (!file.name.startsWith("suckhoe-") || !file.name.toLowerCase().endsWith(".md") || !["text/markdown", "text/plain", "application/octet-stream"].includes(file.mimeType)) {
                continue;
            }
            checked += 1;
            let raw;
            try {
                raw = await this.drive.downloadText(file.id, this.config.maxFileBytes);
            }
            catch {
                index[file.id] = { status: "invalid", checkedAt: new Date().toISOString(), modifiedTime: file.modifiedTime };
                await this.writeIndex(index);
                await this.notifier.invalid(file, "file không đọc được hoặc vượt giới hạn kích thước").catch(() => undefined);
                continue;
            }
            const validation = validateCandidate(raw, this.whitelist, this.config.maxFileBytes);
            if (!validation.ok) {
                index[file.id] = { status: "invalid", checkedAt: new Date().toISOString(), modifiedTime: file.modifiedTime };
                await this.writeIndex(index);
                await this.notifier.invalid(file, friendlyValidationReason(validation.errors)).catch(() => undefined);
                continue;
            }
            const candidate = validation.candidate;
            if (file.name !== `${candidate.metadata.candidate_id}.md`) {
                index[file.id] = { status: "invalid", checkedAt: new Date().toISOString(), candidateId: candidate.metadata.candidate_id, modifiedTime: file.modifiedTime };
                await this.writeIndex(index);
                await this.notifier.invalid(file, "tên file không khớp candidate_id").catch(() => undefined);
                continue;
            }
            if (candidate.metadata.action === "no_change") {
                index[file.id] = { status: "no_change", checkedAt: new Date().toISOString(), candidateId: candidate.metadata.candidate_id, modifiedTime: file.modifiedTime };
                await this.writeIndex(index);
                await this.notifier.noChange(file, candidate.metadata.summary).catch(() => undefined);
                continue;
            }
            let record;
            try {
                record = await this.store.importCandidate({
                    raw,
                    candidate,
                    driveFileId: file.id,
                    driveUrl: file.webViewLink ?? `https://drive.google.com/file/d/${file.id}/view`,
                    approvalTtlDays: this.config.approvalTtlDays,
                });
            }
            catch (error) {
                const duplicate = error instanceof Error && ["drive_file_already_imported", "weekly_candidate_already_exists", "candidate_id_already_exists"].includes(error.message);
                index[file.id] = { status: duplicate ? "duplicate" : "invalid", checkedAt: new Date().toISOString(), candidateId: candidate.metadata.candidate_id, modifiedTime: file.modifiedTime };
                await this.writeIndex(index);
                if (!duplicate)
                    await this.notifier.invalid(file, "không thể stage candidate an toàn").catch(() => undefined);
                continue;
            }
            index[file.id] = {
                status: "imported",
                checkedAt: new Date().toISOString(),
                candidateId: record.candidateId,
                modifiedTime: file.modifiedTime,
                notificationPending: true,
            };
            await this.writeIndex(index);
            imported += 1;
            await this.retryCandidateNotification(file, index[file.id], index);
        }
        await this.writeIndex(index);
        return { checked, imported };
    }
}
