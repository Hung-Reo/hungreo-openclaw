import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [dist, input, output] = process.argv.slice(2);
const legacy = JSON.parse(readFileSync(input, "utf8"));
const { r: projectRetiredHeartbeatConfig } = await import(
  pathToFileURL(path.join(dist, "doctor-heartbeat-legacy-Bq1AWa8M.mjs")).href
);
const projected = projectRetiredHeartbeatConfig(legacy);
if (projected.agents.defaults.heartbeat) {
  throw new Error("OpenClaw did not project the approved heartbeat migration");
}
writeFileSync(output, JSON.stringify(projected), { mode: 0o600 });
