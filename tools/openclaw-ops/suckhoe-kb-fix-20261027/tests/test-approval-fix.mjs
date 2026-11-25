// Test cho bản vá nhắc duyệt + lệnh gõ tay (27/10/2026). Chạy: node tests/test-approval-fix.mjs <thư mục chứa dist/>
// Không gửi gì thật: notifier/store/drive đều là bản giả. Không đụng file live (index ghi vào thư mục tạm).
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = path.resolve(process.argv[2] ?? path.join(path.dirname(new URL(import.meta.url).pathname), "..", "files"));
const { CandidatePoller } = await import(pathToFileURL(path.join(root, "dist/src/poller.js")).href);
const { createReviewCommand, reviewNotification, reminderNotification, expiredNotification } = await import(pathToFileURL(path.join(root, "dist/src/commands.js")).href);

const H = 3600 * 1000;
const DAY = 24 * H;
// 10:00 giờ VN = 03:00Z; 02:00 giờ VN = 19:00Z hôm trước
const DAYTIME = Date.UTC(2026, 10, 1, 3, 0, 0);
const NIGHT = Date.UTC(2026, 10, 1, 19, 0, 0);
let passed = 0;
async function test(name, fn) {
    await fn();
    passed += 1;
    console.log(`PASS ${name}`);
}

function record(over = {}) {
    return { candidateId: "suckhoe-2026-11-01-x", status: "pending", token: "AAAAAAAAAAAAAAAA", title: "T", weekOf: "2026-11-01",
        summary: "S", sourceCount: 4, driveUrl: "https://drive.google.com/file/d/x/view",
        createdAt: new Date(DAYTIME - 25 * H).toISOString(), expiresAt: new Date(DAYTIME + 6 * DAY).toISOString(), ...over };
}
async function setup(records, { notifier = {}, entry = {} } = {}) {
    const dir = await mkdtemp(path.join(os.tmpdir(), "kbfix-"));
    const calls = [];
    const n = {
        candidate: async (r) => calls.push(["candidate", r.token]),
        reminder: async (r) => calls.push(["reminder", r.token]),
        expired: async (r) => calls.push(["expired", r.token]),
        invalid: async () => calls.push(["invalid"]),
        noChange: async () => calls.push(["noChange"]),
        ...notifier,
    };
    const store = { initialize: async () => {}, listRecords: async () => records };
    const drive = { listFiles: async () => [], downloadText: async () => "" };
    const poller = new CandidatePoller({ kbRoot: dir, driveFolderId: "F", maxFileBytes: 1e6, approvalTtlDays: 7 }, [], store, drive, n);
    const index = { file1: { status: "imported", candidateId: "suckhoe-2026-11-01-x", notifiedAt: new Date(DAYTIME - 25 * H).toISOString(), ...entry } };
    return { dir, calls, poller, index, drive, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

await test("thông báo gốc có lệnh gõ tay /kb_review approve <token>", async () => {
    const t = reviewNotification(record()).text;
    assert.match(t, /\/kb_review approve AAAAAAAAAAAAAAAA/);
    assert.match(t, /Nút có hiệu lực 7 ngày/);
});
await test("tin hết hạn có lệnh renew đúng token, không có nút", async () => {
    const m = expiredNotification(record());
    assert.match(m.text, /\/kb_review renew AAAAAAAAAAAAAAAA/);
    assert.equal(m.presentation, undefined);
});
await test("tin nhắc có số giờ còn lại + giữ nút + lệnh gõ tay", async () => {
    const m = reminderNotification(record({ expiresAt: new Date(DAYTIME + 30 * H).toISOString() }), DAYTIME);
    assert.match(m.text, /còn khoảng 30 giờ/);
    assert.ok(m.presentation?.blocks?.length === 1);
    assert.match(m.text, /\/kb_review approve/);
});
await test("pending > 24h ban ngày → nhắc đúng 1 lần, ghi index", async () => {
    const s = await setup([record()]);
    await s.poller.remindPending(s.index, DAYTIME);
    await s.poller.remindPending(s.index, DAYTIME + H);
    assert.deepEqual(s.calls, [["reminder", "AAAAAAAAAAAAAAAA"]]);
    const saved = JSON.parse(await readFile(path.join(s.dir, "medical/review-state/drive-files.json"), "utf8"));
    assert.equal(saved.file1.reminderFor, "AAAAAAAAAAAAAAAA");
    await s.cleanup();
});
await test("pending < 24h → chưa nhắc", async () => {
    const s = await setup([record({ createdAt: new Date(DAYTIME - 23 * H).toISOString() })]);
    await s.poller.remindPending(s.index, DAYTIME);
    assert.deepEqual(s.calls, []);
    await s.cleanup();
});
await test("ban đêm (02:00 VN) → không gửi gì", async () => {
    const s = await setup([record({ createdAt: new Date(NIGHT - 30 * H).toISOString(), expiresAt: new Date(NIGHT - H).toISOString() })]);
    await s.poller.remindPending(s.index, NIGHT);
    assert.deepEqual(s.calls, []);
    await s.cleanup();
});
await test("vừa hết hạn → báo hết hạn đúng 1 lần", async () => {
    const s = await setup([record({ createdAt: new Date(DAYTIME - 8 * DAY).toISOString(), expiresAt: new Date(DAYTIME - H).toISOString() })]);
    await s.poller.remindPending(s.index, DAYTIME);
    await s.poller.remindPending(s.index, DAYTIME + 2 * H);
    assert.deepEqual(s.calls, [["expired", "AAAAAAAAAAAAAAAA"]]);
    await s.cleanup();
});
await test("hết hạn > 7 ngày (kiểu candidate 27/09) → im lặng", async () => {
    const s = await setup([record({ createdAt: new Date(DAYTIME - 30 * DAY).toISOString(), expiresAt: new Date(DAYTIME - 23 * DAY).toISOString() })]);
    await s.poller.remindPending(s.index, DAYTIME);
    assert.deepEqual(s.calls, []);
    await s.cleanup();
});
await test("renew cấp mã mới → tính lại từ renewedAt, nhắc theo mã mới", async () => {
    const r = record({ token: "BBBBBBBBBBBBBBBB", createdAt: new Date(DAYTIME - 10 * DAY).toISOString(),
        renewedAt: new Date(DAYTIME - H).toISOString(), expiresAt: new Date(DAYTIME + 7 * DAY - H).toISOString() });
    const s = await setup([r], { entry: { expiredNoticeFor: "AAAAAAAAAAAAAAAA", reminderFor: "AAAAAAAAAAAAAAAA" } });
    await s.poller.remindPending(s.index, DAYTIME);
    assert.deepEqual(s.calls, []);
    await s.poller.remindPending(s.index, DAYTIME + 25 * H);
    assert.deepEqual(s.calls, [["reminder", "BBBBBBBBBBBBBBBB"]]);
    await s.cleanup();
});
await test("gửi nhắc lỗi → không đánh dấu; thử lại chỉ sau ≥1h", async () => {
    let fail = true;
    const s = await setup([record()], { notifier: { reminder: async () => { if (fail) throw new Error("send failed"); } } });
    await s.poller.remindPending(s.index, DAYTIME);
    assert.equal(s.index.file1.reminderFor, undefined);
    fail = false;
    await s.poller.remindPending(s.index, DAYTIME + 5 * 60000);
    assert.equal(s.index.file1.reminderFor, undefined);
    await s.poller.remindPending(s.index, DAYTIME + 61 * 60000);
    assert.equal(s.index.file1.reminderFor, "AAAAAAAAAAAAAAAA");
    await s.cleanup();
});
await test("CLI giao tin nhưng báo lỗi mãi → tối đa 3 lần gửi/mã (không spam)", async () => {
    let sends = 0;
    const s = await setup([record({ expiresAt: new Date(DAYTIME + 6 * DAY).toISOString() })], { notifier: { reminder: async () => { sends += 1; throw new Error("timeout"); } } });
    for (let i = 0; i < 10; i++) await s.poller.remindPending(s.index, DAYTIME + i * 70 * 60000);
    assert.equal(sends, 3);
    assert.equal(s.index.file1.reminderAttempt.count, 3);
    await s.cleanup();
});
await test("đọc lại sổ cái từ đĩa giữa 2 lượt → không gửi trùng", async () => {
    const s = await setup([record()]);
    await s.poller.remindPending(s.index, DAYTIME);
    const reloaded = await s.poller.readIndex();
    await s.poller.remindPending(reloaded, DAYTIME + 2 * H);
    assert.deepEqual(s.calls, [["reminder", "AAAAAAAAAAAAAAAA"]]);
    await s.cleanup();
});
await test("biên giờ: 06:59 và 21:00 không gửi, 07:00 gửi", async () => {
    const at = (h, m) => Date.UTC(2026, 10, 1, h - 7, m, 0);
    for (const [t, expect] of [[at(6, 59), 0], [at(21, 0), 0], [at(7, 0), 1]]) {
        const s = await setup([record({ createdAt: new Date(t - 25 * H).toISOString(), expiresAt: new Date(t + 5 * DAY).toISOString() })]);
        await s.poller.remindPending(s.index, t);
        assert.equal(s.calls.length, expect);
        await s.cleanup();
    }
});
await test("biên hết hạn: đúng 7 ngày còn báo, quá 7 ngày 1ms im lặng", async () => {
    for (const [ago, expect] of [[7 * DAY, 1], [7 * DAY + 1, 0]]) {
        const s = await setup([record({ createdAt: new Date(DAYTIME - ago - 7 * DAY).toISOString(), expiresAt: new Date(DAYTIME - ago).toISOString() })]);
        await s.poller.remindPending(s.index, DAYTIME);
        assert.equal(s.calls.length, expect);
        await s.cleanup();
    }
});
await test("2 entry cùng candidateId → dùng entry đúng driveFileId", async () => {
    const s = await setup([record({ driveFileId: "file2" })], { entry: { reminderFor: "AAAAAAAAAAAAAAAA" } });
    s.index.file2 = { status: "imported", candidateId: "suckhoe-2026-11-01-x", notifiedAt: new Date(DAYTIME - 25 * H).toISOString() };
    await s.poller.remindPending(s.index, DAYTIME);
    assert.deepEqual(s.calls, [["reminder", "AAAAAAAAAAAAAAAA"]]);
    assert.equal(s.index.file2.reminderFor, "AAAAAAAAAAAAAAAA");
    await s.cleanup();
});
await test("lệnh renew trả tin có lệnh gõ tay với MÃ MỚI", async () => {
    const renewed = record({ token: "CCCCCCCCCCCCCCCC", renewedAt: new Date().toISOString() });
    const cmd = createReviewCommand({ allowedTelegramUserIds: ["42"], approvalTtlDays: 7 }, { renew: async () => renewed });
    const out = await cmd.handler({ senderId: 42, isAuthorizedSender: true, args: "renew AAAAAAAAAAAAAAAA" });
    assert.match(out.text, /\/kb_review approve CCCCCCCCCCCCCCCC/);
    assert.ok(out.presentation?.blocks?.length === 1);
});
await test("record đã duyệt / chưa có notifiedAt → không gửi", async () => {
    const s = await setup([record({ status: "approved" })]);
    await s.poller.remindPending(s.index, DAYTIME);
    const s2 = await setup([record()], { entry: { notifiedAt: undefined } });
    await s2.poller.remindPending(s2.index, DAYTIME);
    assert.deepEqual([...s.calls, ...s2.calls], []);
    await s.cleanup(); await s2.cleanup();
});
await test("index.js cũ không có notifier.reminder → không lỗi, không gửi", async () => {
    const s = await setup([record()], { notifier: { reminder: undefined, expired: undefined } });
    await s.poller.remindPending(s.index, DAYTIME);
    assert.deepEqual(s.calls, []);
    await s.cleanup();
});
await test("pollOnce: nhắc chạy TRƯỚC Drive, Drive lỗi vẫn ném lỗi như cũ", async () => {
    const s = await setup([record()]);
    const order = [];
    s.poller.remindPending = async () => { order.push("remind"); };
    s.drive.listFiles = async () => { order.push("drive"); throw new Error("drive down"); };
    await assert.rejects(() => s.poller.pollOnce(), /drive down/);
    assert.deepEqual(order, ["remind", "drive"]);
    await s.cleanup();
});
await test("pollOnce: remindPending ném lỗi → vẫn poll Drive bình thường", async () => {
    const s = await setup([record()]);
    s.poller.remindPending = async () => { throw new Error("boom"); };
    const res = await s.poller.pollOnce();
    assert.deepEqual(res, { checked: 0, imported: 0 });
    await s.cleanup();
});
console.log(`PASS ${passed}/20 test approval-fix`);
if (passed !== 20) process.exit(1);
