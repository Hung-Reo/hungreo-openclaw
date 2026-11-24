import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { registerHooks } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { checkCommandRegistry } from "./command-registry-gate.mjs";

const entry = path.resolve(process.argv[1]);
const dist = path.dirname(entry);
const target = path.join(dist, "dispatch-from-config-iPVBuUJ4.mjs");
const digest = "ee2b10a04ee662297e492d68a512c6a035c727490c1449e31eeaf4f8bd654574";
const original = readFileSync(target, "utf8");
if (createHash("sha256").update(original).digest("hex") !== digest) {
  throw new Error("Unexpected OpenClaw 11.7 binding implementation");
}

const originalCases = [
  '\t\t\t\tcase "declined":',
  '\t\t\t\tcase "error": {',
  "\t\t\t\t\tconst e = await h();",
  '\t\t\t\t\tif (l.status === "error") logVerbose(`plugin-bound inbound claim failed for ${g.pluginId}: ${l.error}`);',
  '\t\t\t\t\tawait v({ text: l.status === "error" ? buildPluginBindingErrorText(g) : buildPluginBindingDeclinedText(g) }, "terminal", e);',
  "\t\t\t\t\treturn await finishPluginBindingDispatch(l.status);",
  "\t\t\t\t}",
].join("\n");
const preservedCases = [
  '\t\t\t\tcase "declined":',
  "\t\t\t\t\tlogVerbose(`plugin-bound inbound declined by ${g.pluginId}; falling through to OpenClaw agent processing`);",
  "\t\t\t\t\tbreak;",
  '\t\t\t\tcase "error": {',
  "\t\t\t\t\tconst e = await h();",
  "\t\t\t\t\tlogVerbose(`plugin-bound inbound claim failed for ${g.pluginId}: ${l.error}`);",
  '\t\t\t\t\tawait v({ text: buildPluginBindingErrorText(g) }, "terminal", e);',
  "\t\t\t\t\treturn await finishPluginBindingDispatch(l.status);",
  "\t\t\t\t}",
].join("\n");

const offset = original.indexOf(originalCases);
if (offset === -1 || offset !== original.lastIndexOf(originalCases)) {
  throw new Error("Expected exactly one 11.7 binding decline/error branch");
}
const patched = original.replace(originalCases, preservedCases);
const targetUrl = pathToFileURL(target).href;
checkCommandRegistry(dist);
registerHooks({
  load(url, context, nextLoad) {
    const result = nextLoad(url, context);
    if (url !== targetUrl) {
      return result;
    }
    const source =
      typeof result.source === "string"
        ? result.source
        : Buffer.from(result.source ?? "").toString("utf8");
    if (source !== original) {
      throw new Error("OpenClaw 11.7 binding source changed after validation");
    }
    process.stderr.write("PLUGIN_BINDING_DECLINE_FALLBACK_IN_MEMORY 2026.11.7\n");
    return { ...result, source: patched };
  },
});
