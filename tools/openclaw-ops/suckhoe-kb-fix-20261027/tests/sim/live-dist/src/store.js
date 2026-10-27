import { randomBytes } from "node:crypto";
import { constants } from "node:fs";
import { access, mkdir, open, readFile, rename, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { sha256, toApprovedMarkdown, validateCandidate } from "./candidate.js";
export class ReviewStore {
    kbRoot;
    whitelist;
    maxFileBytes;
    reviewDir;
    processedDir;
    approvedDir;
    rejectedDir;
    stateDir;
    logPath;
    constructor(kbRoot, whitelist, maxFileBytes = 262_144) {
        this.kbRoot = kbRoot;
        this.whitelist = whitelist;
        this.maxFileBytes = maxFileBytes;
        const medicalRoot = path.join(kbRoot, "medical");
        this.reviewDir = path.join(medicalRoot, "review");
        this.processedDir = path.join(this.reviewDir, "processed");
        this.approvedDir = path.join(medicalRoot, "approved");
        this.rejectedDir = path.join(medicalRoot, "rejected");
        this.stateDir = path.join(medicalRoot, "review-state");
        this.logPath = path.join(kbRoot, "logs", "weekly-medical.jsonl");
    }
    async initialize() {
        await Promise.all([
            mkdir(this.reviewDir, { recursive: true }),
            mkdir(this.processedDir, { recursive: true }),
            mkdir(this.approvedDir, { recursive: true }),
            mkdir(this.rejectedDir, { recursive: true }),
            mkdir(this.stateDir, { recursive: true }),
            mkdir(path.dirname(this.logPath), { recursive: true }),
        ]);
    }
    statePath(candidateId) {
        return path.join(this.stateDir, `${candidateId}.json`);
    }
    async appendEvent(event) {
        const line = JSON.stringify({ timestamp: new Date().toISOString(), ...event });
        const handle = await open(this.logPath, "a", 0o600);
        try {
            await handle.writeFile(`${line}\n`, "utf8");
        }
        finally {
            await handle.close();
        }
    }
    async writeRecord(record) {
        const target = this.statePath(record.candidateId);
        const temp = `${target}.${process.pid}.tmp`;
        await writeFile(temp, `${JSON.stringify(record, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
        await rename(temp, target);
    }
    async listRecords() {
        await this.initialize();
        const { readdir } = await import("node:fs/promises");
        const names = (await readdir(this.stateDir)).filter((name) => name.startsWith("suckhoe-") && name.endsWith(".json"));
        const records = [];
        for (const name of names) {
            try {
                records.push(JSON.parse(await readFile(path.join(this.stateDir, name), "utf8")));
            }
            catch {
                // A malformed state file is ignored here and remains visible for operator inspection.
            }
        }
        return records;
    }
    async importCandidate(input) {
        await this.initialize();
        const meta = input.candidate.metadata;
        const existing = await this.listRecords();
        const inputHash = sha256(input.raw);
        const existingDriveFile = existing.find((record) => record.driveFileId === input.driveFileId);
        if (existingDriveFile && existingDriveFile.status !== "rejected") {
            throw new Error("drive_file_already_imported");
        }
        const existingWeek = existing.find((record) => record.weekOf === meta.week_of);
        if (existingWeek) {
            if (existingWeek.status !== "rejected")
                throw new Error("weekly_candidate_already_exists");
            if (existingWeek.sha256 === inputHash)
                throw new Error("rejected_candidate_unchanged");
        }
        const candidatePath = path.join(this.reviewDir, `${meta.candidate_id}.md`);
        try {
            await access(candidatePath, constants.F_OK);
            throw new Error("candidate_id_already_exists");
        }
        catch (error) {
            if (error instanceof Error && error.message === "candidate_id_already_exists")
                throw error;
        }
        const now = new Date();
        const expires = new Date(now.getTime() + input.approvalTtlDays * 86_400_000);
        const record = {
            candidateId: meta.candidate_id,
            token: randomBytes(12).toString("base64url"),
            status: "pending",
            weekOf: meta.week_of,
            topic: meta.topic,
            title: meta.title,
            summary: meta.summary,
            sourceCount: meta.sources.length,
            candidatePath,
            sha256: inputHash,
            driveFileId: input.driveFileId,
            driveUrl: input.driveUrl,
            createdAt: now.toISOString(),
            expiresAt: expires.toISOString(),
        };
        await writeFile(candidatePath, input.raw, { encoding: "utf8", mode: 0o600, flag: "wx" });
        try {
            await this.writeRecord(record);
        }
        catch (error) {
            await unlink(candidatePath).catch(() => undefined);
            throw error;
        }
        await this.appendEvent({
            event: existingWeek ? "candidate_revision_imported" : "candidate_imported",
            candidate_id: record.candidateId,
            drive_file_id: record.driveFileId,
        });
        return record;
    }
    async findByToken(token) {
        const records = await this.listRecords();
        return records.find((record) => record.token === token) ?? null;
    }
    async show(token) {
        const record = await this.findByToken(token);
        if (!record)
            throw new Error("review_token_not_found");
        return record;
    }
    async renew(token, reviewerId, approvalTtlDays = 7) {
        if (!Number.isInteger(approvalTtlDays) || approvalTtlDays < 1 || approvalTtlDays > 30)
            throw new Error("invalid_approval_ttl");
        const record = await this.findByToken(token);
        if (!record) throw new Error("review_token_not_found");
        const lockPath = `${this.statePath(record.candidateId)}.lock`;
        let lock;
        try { lock = await open(lockPath, "wx", 0o600); }
        catch { throw new Error("review_decision_in_progress"); }
        try {
            const current = JSON.parse(await readFile(this.statePath(record.candidateId), "utf8"));
            if (current.token !== token) throw new Error("review_token_not_found");
            if (current.status !== "pending") throw new Error(`review_already_${current.status}`);
            const expiry = Date.parse(current.expiresAt);
            if (!Number.isFinite(expiry)) throw new Error("invalid_review_expiry");
            if (expiry > Date.now()) throw new Error("review_token_still_valid");
            const raw = await readFile(current.candidatePath, "utf8");
            if (sha256(raw) !== current.sha256) throw new Error("candidate_hash_changed");
            const validation = validateCandidate(raw, this.whitelist, this.maxFileBytes);
            if (!validation.ok) throw new Error(`candidate_revalidation_failed:${validation.errors.join(",")}`);
            const now = new Date();
            current.token = randomBytes(12).toString("base64url");
            current.expiresAt = new Date(now.getTime() + approvalTtlDays * 86400000).toISOString();
            current.renewedAt = now.toISOString();
            current.renewedBy = reviewerId;
            // Write intent before mutation; no token values belong in the audit log.
            await this.appendEvent({ event: "review_renewal_requested", candidate_id: current.candidateId, reviewer_id: reviewerId });
            await this.writeRecord(current);
            await this.appendEvent({ event: "review_token_renewed", candidate_id: current.candidateId, reviewer_id: reviewerId });
            return current;
        } finally {
            await lock.close();
            await unlink(lockPath).catch(() => undefined);
        }
    }
    async decide(token, decision, reviewerId) {
        const record = await this.findByToken(token);
        if (!record)
            throw new Error("review_token_not_found");
        const lockPath = `${this.statePath(record.candidateId)}.lock`;
        let lock;
        try {
            lock = await open(lockPath, "wx", 0o600);
        }
        catch {
            throw new Error("review_decision_in_progress");
        }
        try {
            const current = JSON.parse(await readFile(this.statePath(record.candidateId), "utf8"));
            if (current.token !== token) throw new Error("review_token_not_found");
            if (current.status !== "pending")
                throw new Error(`review_already_${current.status}`);
            if (!Number.isFinite(Date.parse(current.expiresAt)) || Date.parse(current.expiresAt) <= Date.now())
                throw new Error("review_token_expired");
            const raw = await readFile(current.candidatePath, "utf8");
            if (sha256(raw) !== current.sha256)
                throw new Error("candidate_hash_changed");
            const decidedAt = new Date().toISOString();
            if (decision === "approve") {
                const validation = validateCandidate(raw, this.whitelist, this.maxFileBytes);
                if (!validation.ok)
                    throw new Error(`candidate_revalidation_failed:${validation.errors.join(",")}`);
                if (validation.candidate.metadata.action === "no_change") {
                    throw new Error("no_change_candidate_cannot_be_approved");
                }
                const approvedPath = path.join(this.approvedDir, `${current.candidateId}.md`);
                await writeFile(approvedPath, toApprovedMarkdown(validation.candidate, reviewerId, decidedAt), { encoding: "utf8", mode: 0o600, flag: "wx" });
                await rename(current.candidatePath, path.join(this.processedDir, `${current.candidateId}.md`));
                current.status = "approved";
            }
            else {
                const revisionStamp = current.createdAt.replace(/\D/g, "").slice(0, 14);
                const rejectedName = `${current.candidateId}-${revisionStamp}-${current.sha256.slice(0, 12)}.md`;
                await rename(current.candidatePath, path.join(this.rejectedDir, rejectedName));
                current.status = "rejected";
            }
            current.decidedAt = decidedAt;
            current.decidedBy = reviewerId;
            await this.writeRecord(current);
            await this.appendEvent({ event: `candidate_${current.status}`, candidate_id: current.candidateId, reviewer_id: reviewerId });
            return current;
        }
        finally {
            await lock.close();
            await unlink(lockPath).catch(() => undefined);
        }
    }
}
