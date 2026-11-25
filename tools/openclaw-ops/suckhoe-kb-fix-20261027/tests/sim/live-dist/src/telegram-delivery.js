import { execFile } from "node:child_process";
import { promisify } from "node:util";
const execFileAsync = promisify(execFile);
const defaultRunner = async (file, args, options) => {
    const result = await execFileAsync(file, args, options);
    return { stdout: result.stdout, stderr: result.stderr };
};
export async function sendTelegramViaCli(config, text, presentation, runner = defaultRunner) {
    const args = [
        "message",
        "send",
        "--channel",
        "telegram",
        "--target",
        config.reviewChatId,
        "--message",
        text,
    ];
    if (presentation)
        args.push("--presentation", JSON.stringify(presentation));
    args.push("--json");
    await runner(config.openclawBin, args, {
        env: {
            ...process.env,
            OPENCLAW_STATE_DIR: config.openclawStateDir,
            OPENCLAW_CONFIG_PATH: config.openclawConfigPath,
        },
        timeout: 60_000,
        maxBuffer: 1_048_576,
        shell: false,
    });
}
