import { createSign } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
function base64url(value) {
    return Buffer.from(value).toString("base64url");
}
export class ServiceAccountDriveReader {
    serviceAccountPath;
    fetchImpl;
    token = null;
    constructor(serviceAccountPath, fetchImpl = fetch) {
        this.serviceAccountPath = serviceAccountPath;
        this.fetchImpl = fetchImpl;
    }
    async readCredentials() {
        const fileStat = await stat(this.serviceAccountPath);
        if ((fileStat.mode & 0o077) !== 0)
            throw new Error("drive_service_account_permissions_unsafe");
        const parsed = JSON.parse(await readFile(this.serviceAccountPath, "utf8"));
        if (!parsed.client_email || !parsed.private_key)
            throw new Error("drive_service_account_invalid");
        return parsed;
    }
    async accessToken() {
        if (this.token && this.token.expiresAt - Date.now() > 60_000)
            return this.token.value;
        const account = await this.readCredentials();
        const now = Math.floor(Date.now() / 1000);
        const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
        const claims = base64url(JSON.stringify({
            iss: account.client_email,
            scope: "https://www.googleapis.com/auth/drive.readonly",
            aud: account.token_uri ?? "https://oauth2.googleapis.com/token",
            iat: now,
            exp: now + 3600,
        }));
        const unsigned = `${header}.${claims}`;
        const signer = createSign("RSA-SHA256");
        signer.update(unsigned);
        signer.end();
        const assertion = `${unsigned}.${signer.sign(account.private_key).toString("base64url")}`;
        const body = new URLSearchParams({
            grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
            assertion,
        });
        const response = await this.fetchImpl(account.token_uri ?? "https://oauth2.googleapis.com/token", {
            method: "POST",
            headers: { "content-type": "application/x-www-form-urlencoded" },
            body,
        });
        if (!response.ok)
            throw new Error(`drive_token_failed:${response.status}`);
        const result = await response.json();
        if (!result.access_token)
            throw new Error("drive_token_missing");
        this.token = {
            value: result.access_token,
            expiresAt: Date.now() + (result.expires_in ?? 3600) * 1000,
        };
        return this.token.value;
    }
    async request(url) {
        const token = await this.accessToken();
        const response = await this.fetchImpl(url, { headers: { authorization: `Bearer ${token}` } });
        if (!response.ok)
            throw new Error(`drive_request_failed:${response.status}`);
        return response;
    }
    async listFiles(folderId) {
        const params = new URLSearchParams({
            q: `'${folderId}' in parents and trashed = false`,
            fields: "files(id,name,mimeType,size,createdTime,modifiedTime,webViewLink)",
            orderBy: "createdTime desc",
            pageSize: "20",
            spaces: "drive",
        });
        const result = await (await this.request(`https://www.googleapis.com/drive/v3/files?${params}`)).json();
        return result.files ?? [];
    }
    async downloadText(fileId, maxBytes) {
        const response = await this.request(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media`);
        const contentLength = Number(response.headers.get("content-length") ?? 0);
        if (contentLength > maxBytes)
            throw new Error("drive_file_too_large");
        const bytes = Buffer.from(await response.arrayBuffer());
        if (bytes.byteLength > maxBytes)
            throw new Error("drive_file_too_large");
        return bytes.toString("utf8");
    }
}
