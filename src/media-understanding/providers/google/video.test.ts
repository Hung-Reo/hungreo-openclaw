import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const TEST_NET_IP = "203.0.113.10";

const resolveRequestUrl = (input: RequestInfo | URL) => {
  if (typeof input === "string") {
    return input;
  }
  if (input instanceof URL) {
    return input.toString();
  }
  return input.url;
};

describe("describeGeminiVideo", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.doMock("../../../infra/net/ssrf.js", async () => {
      const actual = await vi.importActual<typeof import("../../../infra/net/ssrf.js")>(
        "../../../infra/net/ssrf.js",
      );
      const resolvePinned = async (hostname: string) => {
        const normalized = hostname.trim().toLowerCase().replace(/\.$/, "");
        const addresses = [TEST_NET_IP];
        return {
          hostname: normalized,
          addresses,
          lookup: actual.createPinnedLookup({ hostname: normalized, addresses }),
        };
      };
      return {
        ...actual,
        resolvePinnedHostname: vi.fn(resolvePinned),
        resolvePinnedHostnameWithPolicy: vi.fn(resolvePinned),
      };
    });
  });

  afterEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
  });

  it("respects case-insensitive x-goog-api-key overrides", async () => {
    const { describeGeminiVideo } = await import("./video.js");
    let seenKey: string | null = null;
    const fetchFn = async (_input: RequestInfo | URL, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      seenKey = headers.get("x-goog-api-key");
      return new Response(
        JSON.stringify({
          candidates: [{ content: { parts: [{ text: "video ok" }] } }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    };

    const result = await describeGeminiVideo({
      buffer: Buffer.from("video"),
      fileName: "clip.mp4",
      apiKey: "test-key",
      timeoutMs: 1000,
      headers: { "X-Goog-Api-Key": "override" },
      fetchFn,
    });

    expect(seenKey).toBe("override");
    expect(result.text).toBe("video ok");
  });

  it("builds the expected request payload", async () => {
    const { describeGeminiVideo } = await import("./video.js");
    let seenUrl: string | null = null;
    let seenInit: RequestInit | undefined;
    const fetchFn = async (input: RequestInfo | URL, init?: RequestInit) => {
      seenUrl = resolveRequestUrl(input);
      seenInit = init;
      return new Response(
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [{ text: "first" }, { text: " second " }, { text: "" }],
              },
            },
          ],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    };

    const result = await describeGeminiVideo({
      buffer: Buffer.from("video-bytes"),
      fileName: "clip.mp4",
      apiKey: "test-key",
      timeoutMs: 1500,
      baseUrl: "https://example.com/v1beta/",
      model: "gemini-3-pro",
      headers: { "X-Other": "1" },
      fetchFn,
    });

    expect(result.model).toBe("gemini-3-pro-preview");
    expect(result.text).toBe("first\nsecond");
    expect(seenUrl).toBe("https://example.com/v1beta/models/gemini-3-pro-preview:generateContent");
    expect(seenInit?.method).toBe("POST");
    expect(seenInit?.signal).toBeInstanceOf(AbortSignal);

    const headers = new Headers(seenInit?.headers);
    expect(headers.get("x-goog-api-key")).toBe("test-key");
    expect(headers.get("content-type")).toBe("application/json");
    expect(headers.get("x-other")).toBe("1");

    const bodyText =
      typeof seenInit?.body === "string"
        ? seenInit.body
        : Buffer.isBuffer(seenInit?.body)
          ? seenInit.body.toString("utf8")
          : "";
    const body = JSON.parse(bodyText);
    expect(body.contents?.[0]?.parts?.[0]?.text).toBe("Describe the video.");
    expect(body.contents?.[0]?.parts?.[1]?.inline_data?.mime_type).toBe("video/mp4");
    expect(body.contents?.[0]?.parts?.[1]?.inline_data?.data).toBe(
      Buffer.from("video-bytes").toString("base64"),
    );
  });
});
