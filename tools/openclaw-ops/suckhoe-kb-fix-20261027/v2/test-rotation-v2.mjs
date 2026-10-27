#!/usr/bin/env node
// Test suite cho rotation v2 (8 -> 17 chủ đề; `skin` chèn idx 0 ngày 2026-10-26).
// Chạy:  node test-rotation-v2.mjs
// Exit 0 = tất cả pass. Exit 1 = có test fail.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
    ALL_TOPICS,
    expectedTopic,
    weekIndexOf,
    rotationVersionOf,
    validateCandidate,
    loadWhitelist,
} from "./candidate.js";
import { validateCandidateFile } from "./preflight.js";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ANCHOR_UTC = Date.UTC(2026, 6, 19);

let passed = 0;
const failures = [];

function check(name, actual, expected) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) {
        passed += 1;
    } else {
        failures.push(`${name}\n      mong đợi: ${e}\n      nhận được: ${a}`);
    }
}
function ok(name, condition, detail = "") {
    if (condition) passed += 1;
    else failures.push(`${name}${detail ? `\n      ${detail}` : ""}`);
}
function section(title) {
    console.log(`\n${title}`);
}
/** week index -> "YYYY-MM-DD" (Chủ Nhật) */
function weekOf(week) {
    return new Date(ANCHOR_UTC + week * 7 * 86_400_000).toISOString().slice(0, 10);
}

const V1 = [
    "diabetes", "hypertension", "hepatitis-b", "bones-and-joints",
    "mental-health", "dengue", "stroke-and-heart", "child-health",
];
const V2 = [
    "skin", "diabetes", "medication-safety", "hypertension", "respiratory",
    "hepatitis-b", "digestive", "bones-and-joints", "elderly-health",
    "mental-health", "first-aid", "dengue", "kidney-urinary",
    "stroke-and-heart", "womens-health", "child-health", "cancer-screening",
];
const V2_START_WEEK = 16;

// ---------------------------------------------------------------------------
section("1. REGRESSION — 10 candidate đã tồn tại trong Suckhoe KB Inbox");
// ---------------------------------------------------------------------------
const existing = [
    ["2026-07-19", "diabetes"],
    ["2026-07-26", "hypertension"],
    ["2026-08-02", "hepatitis-b"],
    ["2026-08-09", "bones-and-joints"],
    ["2026-08-16", "mental-health"],
    ["2026-08-23", "dengue"],
    ["2026-08-30", "stroke-and-heart"],
    ["2026-09-06", "child-health"],
    ["2026-09-13", "diabetes"],
    ["2026-10-04", "bones-and-joints"],
];
for (const [week, topic] of existing) {
    check(`   ${week} vẫn map đúng -> ${topic}`, expectedTopic(week), topic);
}

// ---------------------------------------------------------------------------
section("2. V1 ERA — tuần 0..15 phải giữ nguyên hành vi cũ (modulo 8)");
// ---------------------------------------------------------------------------
for (let w = 0; w < V2_START_WEEK; w += 1) {
    check(`   tuần ${String(w).padStart(2)} (${weekOf(w)})`, expectedTopic(weekOf(w)), V1[w % 8]);
}
check("   tuần 15 = 2026-11-01", weekOf(15), "2026-11-01");
check("   V1 chạy trọn 2 vòng rồi mới cắt (tuần 15 = chủ đề cuối V1)", expectedTopic("2026-11-01"), "child-health");

// ---------------------------------------------------------------------------
section("3. CUTOVER — V2 bắt đầu đúng tuần 16 = 2026-11-08");
// ---------------------------------------------------------------------------
check("   tuần 16 = 2026-11-08", weekOf(16), "2026-11-08");
check("   rotationVersion tuần 15", rotationVersionOf("2026-11-01"), 1);
check("   rotationVersion tuần 16", rotationVersionOf("2026-11-08"), 2);
check("   tuần 16 -> skin (V2 idx 0)", expectedTopic("2026-11-08"), "skin");
check("   tuần 17 -> diabetes (V2 idx 1)", expectedTopic("2026-11-15"), "diabetes");
check("   tuần 18 -> medication-safety", expectedTopic("2026-11-22"), "medication-safety");

// ---------------------------------------------------------------------------
section("4. V2 CYCLE — tuần 16..32 phủ đúng 17 chủ đề, tuần 33 quay vòng");
// ---------------------------------------------------------------------------
for (let i = 0; i < 17; i += 1) {
    const w = V2_START_WEEK + i;
    check(`   idx ${String(i).padStart(2)} tuần ${w} (${weekOf(w)})`, expectedTopic(weekOf(w)), V2[i]);
}
const cycle1 = Array.from({ length: 17 }, (_, i) => expectedTopic(weekOf(V2_START_WEEK + i)));
ok("   một vòng V2 phủ đủ 17 chủ đề khác nhau", new Set(cycle1).size === 17, `nhận được ${new Set(cycle1).size}`);
check("   tuần 33 quay lại đầu vòng V2", expectedTopic(weekOf(33)), V2[0]);
check("   tuần 34 tiếp tục đúng thứ tự", expectedTopic(weekOf(34)), V2[1]);
check("   tuần 32 = cancer-screening (cuối vòng)", expectedTopic(weekOf(32)), "cancer-screening");

// ---------------------------------------------------------------------------
section("5. DANH SÁCH CHỦ ĐỀ — 17 slug, không trùng, không mất chủ đề cũ");
// ---------------------------------------------------------------------------
check("   tổng số chủ đề hợp lệ", ALL_TOPICS.length, 17);
ok("   có chủ đề skin", ALL_TOPICS.includes("skin"));
for (const t of V1) ok(`   giữ lại chủ đề cũ "${t}"`, ALL_TOPICS.includes(t));
for (const t of V2.filter((x) => !V1.includes(x))) ok(`   thêm chủ đề mới "${t}"`, ALL_TOPICS.includes(t));

// ---------------------------------------------------------------------------
section("6. CANDIDATE_ID — regex chấp nhận slug mới, từ chối slug lạ");
// ---------------------------------------------------------------------------
const whitelist = await loadWhitelist(path.join(HERE, "medical-consumer-health-whitelist.txt"));

function candidateStub({ id, week, topic, action = "create" }) {
    const meta = {
        schema_version: 1,
        candidate_id: id,
        policy_version: "consumer-health-v1",
        week_of: week,
        topic,
        action,
        generated_at: "2026-11-08T01:00:00+07:00",
        title: "Tiêu đề thử nghiệm",
        medical_system: "test",
        tags: ["test"],
        confidence: "medium",
        summary: "Bản thử nghiệm dùng cho test vòng xoay.",
        sources: action === "create"
            ? [{ id: "S1", title: "Neck pain", publisher: "NHS", url: "https://www.nhs.uk/symptoms/neck-pain-and-stiff-neck/", accessed_at: "2026-11-08" }]
            : [],
        claims: action === "create" ? [{ id: "C1", summary: "Claim thử nghiệm.", source_ids: ["S1"] }] : [],
    };
    const body = action === "create"
        ? ["# Tiêu đề thử nghiệm", "## Dùng khi nào", "x", "## Ý chính", "- Nội dung [S1].",
            "## Theo dõi tại nhà", "x", "## Red flags", "x", "## Khi nào đi khám", "x",
            "## Không nên nói quá mức", "x", "## Nguồn",
            "- [S1] https://www.nhs.uk/symptoms/neck-pain-and-stiff-neck/"].join("\n\n")
        : ["# Tiêu đề thử nghiệm", "Không đủ nội dung mới trong tuần này."].join("\n\n");
    return `<!-- suckhoe-kb-candidate:v1\n${JSON.stringify(meta, null, 2)}\n-->\n\n${body}\n`;
}
function errorsFor(args) {
    const r = validateCandidate(candidateStub(args), whitelist);
    return r.ok ? [] : r.errors;
}

// Mỗi chủ đề mới phải qua được toàn bộ validator ở đúng tuần của nó.
for (let i = 0; i < 17; i += 1) {
    const w = V2_START_WEEK + i;
    const week = weekOf(w);
    const topic = V2[i];
    check(`   candidate hợp lệ cho "${topic}" @ ${week}`,
        errorsFor({ id: `suckhoe-${week}-${topic}`, week, topic }), []);
}
ok("   từ chối slug không có trong vòng xoay",
    errorsFor({ id: "suckhoe-2026-11-08-acupuncture", week: "2026-11-08", topic: "acupuncture" })
        .includes("candidate_id_invalid"));
check("   chấp nhận hậu tố revision (-v2)",
    errorsFor({ id: "suckhoe-2026-11-22-medication-safety-v2", week: "2026-11-22", topic: "medication-safety" }),
    ["candidate_id_metadata_mismatch"]);

// ---------------------------------------------------------------------------
section("7. GUARD CŨ vẫn hoạt động");
// ---------------------------------------------------------------------------
ok("   topic_rotation_mismatch khi gắn sai chủ đề vào tuần",
    errorsFor({ id: "suckhoe-2026-11-08-first-aid", week: "2026-11-08", topic: "first-aid" })
        .includes("topic_rotation_mismatch"));
ok("   topic_rotation_mismatch khi week_of không phải Chủ Nhật đúng vòng",
    errorsFor({ id: "suckhoe-2026-11-09-skin", week: "2026-11-09", topic: "skin" })
        .includes("topic_rotation_mismatch"));
ok("   candidate_id_metadata_mismatch khi id lệch metadata",
    errorsFor({ id: "suckhoe-2026-11-08-hypertension", week: "2026-11-08", topic: "skin" })
        .includes("candidate_id_metadata_mismatch"));
ok("   no_change vẫn hợp lệ với chủ đề mới",
    errorsFor({ id: "suckhoe-2026-11-08-skin", week: "2026-11-08", topic: "skin", action: "no_change" }).length === 0);
check("   week_of trước anchor bị từ chối", expectedTopic("2026-07-12"), null);
check("   week_of không hợp lệ bị từ chối", weekIndexOf("2026-02-30"), null);

// ---------------------------------------------------------------------------
ok("   diabetes ở 2026-11-08 (lịch V2 cũ) giờ bị từ chối",
    errorsFor({ id: "suckhoe-2026-11-08-diabetes", week: "2026-11-08", topic: "diabetes" })
        .includes("topic_rotation_mismatch"));

// ---------------------------------------------------------------------------
section("8. END-TO-END — preflight thật trên file candidate thật");
// ---------------------------------------------------------------------------
for (const name of ["suckhoe-2026-09-13-diabetes.md", "suckhoe-2026-10-04-bones-and-joints.md"]) {
    const result = await validateCandidateFile(path.join(HERE, "fixtures", name), whitelist);
    check(`   ${name}`, result, { ok: true, errors: [] });
}

// ---------------------------------------------------------------------------
section("9. CHỨNG MINH vì sao KHÔNG dùng cách append vào V1");
// ---------------------------------------------------------------------------
function naiveAppend(week, extra) {
    const rot = [...V1, ...Array.from({ length: extra }, (_, i) => `new${i + 1}`)];
    return rot[week % rot.length];
}
for (const extra of [1, 4, 8]) {
    const broken = existing.filter(([w, t]) => naiveAppend(weekIndexOf(w), extra) !== t);
    ok(`   append +${extra} chủ đề => ${broken.length} candidate cũ sẽ fail (đúng như dự đoán)`,
        broken.length > 0, "nếu không fail thì lập luận tách version đã sai");
}
const brokenNow = existing.filter(([w, t]) => expectedTopic(w) !== t);
ok("   cách tách version => 0 candidate cũ fail", brokenNow.length === 0,
    `đang fail: ${brokenNow.map(([w]) => w).join(", ")}`);

// ---------------------------------------------------------------------------
console.log(`\n${"=".repeat(64)}`);
if (failures.length === 0) {
    console.log(`PASS — ${passed}/${passed} test`);
    process.exit(0);
} else {
    console.log(`FAIL — ${passed} pass, ${failures.length} fail\n`);
    for (const f of failures) console.log(`  x ${f}`);
    process.exit(1);
}
