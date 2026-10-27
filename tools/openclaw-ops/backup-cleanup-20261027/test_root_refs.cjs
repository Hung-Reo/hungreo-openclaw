const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync(__dirname + "/root_refs.js", "utf8");
const target = "/home/hung/backups/old";

function check({
  mapPath = "",
  mountPath = "/",
  mountRoot = "/",
  denied = false,
  fdPath = "",
} = {}) {
  let result, exitCode;
  const fake = {
    readdirSync(path) {
      if (path === "/proc") {
        return ["101", "self"];
      }
      if (path === "/proc/101/fd") {
        return fdPath ? ["5"] : [];
      }
      throw Error("unexpected directory");
    },
    readlinkSync(path) {
      if (path.endsWith("/ns/mnt")) {
        return "mnt:[123]";
      }
      if (path.endsWith("/fd/5")) {
        return fdPath;
      }
      if (path.endsWith("/exe")) {
        return "/usr/bin/node";
      }
      return "/";
    },
    readFileSync(path) {
      if (path === "/targets.json") {
        return JSON.stringify({ paths: [target] });
      }
      if (path === "/proc/1/mountinfo") {
        return "1 0 8:1 / / rw - ext4 /dev/sda1 rw\n";
      }
      if (path.endsWith("/mountinfo")) {
        return `1 0 8:1 ${mountRoot} ${mountPath} rw - ext4 /dev/sda1 rw\n`;
      }
      if (path.endsWith("/maps")) {
        if (denied) {
          throw Object.assign(Error("denied"), { code: "EACCES" });
        }
        return mapPath ? `0000-0001 r--p 0 08:01 42 ${mapPath}\n` : "";
      }
      throw Error("unexpected file");
    },
  };
  vm.runInNewContext(source, {
    require(name) {
      assert.equal(name, "node:fs");
      return fake;
    },
    console: {
      log(value) {
        result = JSON.parse(value);
      },
    },
    process: {
      exit(code) {
        exitCode = code;
      },
    },
    Date,
  });
  return { result, exitCode };
}

assert.equal(check().exitCode, 0);
assert.equal(check({ denied: true }).exitCode, 1);
assert.equal(check({ mapPath: target + "/file" }).exitCode, 1);
assert.equal(check({ fdPath: target + "/file" }).exitCode, 1);
assert.equal(check({ mountPath: target + "/mounted" }).exitCode, 1);
assert.equal(check({ mountPath: target + ".cleanup-20261027-pending" }).exitCode, 1);
assert.equal(check({ mapPath: target + "-other/file" }).exitCode, 0);
assert.equal(check({ mountRoot: target, mountPath: "/mnt/alias" }).exitCode, 1);
assert.equal(check({ mountRoot: "/home/hung/backups", mountPath: "/mnt/alias" }).exitCode, 1);
assert.equal(check({ mountRoot: "/unrelated", mountPath: "/mnt/alias" }).exitCode, 0);
console.log("10 metadata-helper guard scenarios PASS");
