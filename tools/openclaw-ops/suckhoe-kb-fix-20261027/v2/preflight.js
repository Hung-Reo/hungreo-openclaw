import path from "node:path";
import { readFile } from "node:fs/promises";
import { validateCandidate } from "./candidate.js";
export async function validateCandidateFile(filePath, whitelist, maxFileBytes = 262_144) {
    const raw = await readFile(filePath, "utf8");
    const validation = validateCandidate(raw, whitelist, maxFileBytes);
    if (!validation.ok) {
        return { ok: false, errors: validation.errors };
    }
    const expectedName = `${validation.candidate.metadata.candidate_id}.md`;
    if (path.basename(filePath) !== expectedName) {
        return { ok: false, errors: ["filename_candidate_id_mismatch"] };
    }
    return { ok: true, errors: [] };
}
