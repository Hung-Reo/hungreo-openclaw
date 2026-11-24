import { readFileSync } from "node:fs";
import path from "node:path";

export function checkCommandRegistry(dist) {
  const read = (name) => readFileSync(path.join(dist, name), "utf8");
  const loader = read("loader-runtime-load-WYnVk_Xr.mjs");
  const registration = read("command-registration-CbYGQF9D.mjs");
  const list = read("plugin-command-registry-Djk4s-ty.mjs");
  const state = read("command-registry-state-B0EzgaBs.mjs");
  const runtime = read("runtime-BtPD3SRP.mjs");
  if (
    loader.includes("restorePluginCommands(") ||
    !loader.includes("activatePluginRegistry(t, s.cacheKey") ||
    !loader.includes("activatePluginRegistry(b, s.cacheKey") ||
    !registration.includes("r?.registry ?? requireActivePluginRegistry()") ||
    !list.includes("return e.commands.map(") ||
    !state.includes("listRegisteredPluginCommands(requireActivePluginRegistry())") ||
    !runtime.includes("const e = getPluginRegistryForContext();")
  ) {
    throw new Error("Expected scoped OpenClaw 11.7 command registry");
  }
}
