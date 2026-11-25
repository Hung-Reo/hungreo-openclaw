import {
  existsSync,
  lstatSync,
  readFileSync,
  realpathSync,
  renameSync,
  symlinkSync,
} from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

const [profile, core] = process.argv.slice(2);
const projects = path.join(profile, "npm", "projects");
const db = new DatabaseSync(path.join(profile, "state", "openclaw.sqlite"), { readOnly: true });
const index = db
  .prepare("select value_json from config_machine_state where state_key = 'plugins.installedIndex'")
  .get();
db.close();
const records = JSON.parse(index.value_json).index.installRecords;

const expected = new Map([
  ["brave", "2026.11.7"],
  ["codex", "2026.11.7"],
  ["deepseek", "2026.11.7"],
  ["parallel", "2026.11.7"],
  ["typesafe", "2026.11.7"],
  ["lossless-claw", "1.2.0"],
]);

function sameProfile(target) {
  return target.startsWith(projects + path.sep);
}

function link(target) {
  if (!sameProfile(target)) {
    throw new Error("Refusing peer link outside the working profile");
  }
  if (!existsSync(path.dirname(target))) {
    return;
  }
  try {
    const current = lstatSync(target);
    if (!current.isSymbolicLink()) {
      throw new Error("Non-symlink OpenClaw peer; inspect plugin install first");
    }
    if (realpathSync(target) === realpathSync(core)) {
      return;
    }
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  const temporary = target + ".hungreo-117-" + process.pid;
  symlinkSync(core, temporary);
  renameSync(temporary, target);
  if (realpathSync(target) !== realpathSync(core)) {
    throw new Error("OpenClaw peer link not established");
  }
}

for (const [id, version] of expected) {
  const record = records[id];
  if (!record || record.version !== version || !sameProfile(realpathSync(record.installPath))) {
    throw new Error("Unexpected plugin install record: " + id);
  }
  const directory = realpathSync(record.installPath);
  const packageJson = JSON.parse(readFileSync(path.join(directory, "package.json"), "utf8"));
  if (packageJson.version !== version) {
    throw new Error("Unexpected plugin package version: " + id);
  }
  if (id === "codex" && packageJson.dependencies["@openai/codex"] !== "0.170.0") {
    throw new Error("Codex plugin uses an unexpected app-server version");
  }
  let npmModules = path.dirname(directory);
  if (path.basename(npmModules).startsWith("@")) {
    npmModules = path.dirname(npmModules);
  }
  if (path.basename(npmModules) !== "node_modules") {
    throw new Error("Unexpected npm plugin layout: " + id);
  }
  link(path.join(npmModules, "openclaw"));
  link(path.join(directory, "node_modules", "openclaw"));
}
console.log("official_plugins=2026.11.7 codex=0.170.0 lossless-claw=1.2.0 peer_links=verified");
