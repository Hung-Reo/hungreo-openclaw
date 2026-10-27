// Metadata only: no cmdline, environ, credentials, databases or host file contents.
const fs = require("node:fs");
const targets = JSON.parse(fs.readFileSync("/targets.json", "utf8")).paths;
let matches = 0,
  permissionDenials = 0,
  processes = 0;
const denied = (e) => {
  if (["EACCES", "EPERM"].includes(e.code)) {
    permissionDenials++;
  } else if (!["ENOENT", "ESRCH", "EINVAL"].includes(e.code)) {
    throw e;
  }
};
const match = (value) => {
  if (targets.some((t) => value === t || value.startsWith(t + "/"))) {
    matches++;
  }
};
for (const pid of fs.readdirSync("/proc").filter((x) => /^\d+$/.test(x))) {
  processes++;
  try {
    for (const line of fs.readFileSync("/proc/" + pid + "/maps", "utf8").split("\n")) {
      const path = line.trim().split(/\s+/).slice(5).join(" ");
      match(path);
    }
  } catch (e) {
    denied(e);
  }
  const links = ["cwd", "exe", "root"];
  try {
    links.push(...fs.readdirSync("/proc/" + pid + "/fd").map((n) => "fd/" + n));
  } catch (e) {
    denied(e);
  }
  for (const link of links) {
    try {
      match(fs.readlinkSync("/proc/" + pid + "/" + link));
    } catch (e) {
      denied(e);
    }
  }
}
console.log(JSON.stringify({ matches, permissionDenials, processes, epoch: Date.now() / 1000 }));
process.exit(matches === 0 && permissionDenials === 0 ? 0 : 1);
