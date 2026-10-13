import { afterEach, describe, expect, it, vi } from "vitest";
import { edgeListeners, edgeListenerConfig } from "./edge-listeners";
import { bakedEdgeNginxConf } from "./edge-baked-conf";

afterEach(() => vi.unstubAllEnvs());

describe("Apache front-proxy listeners", () => {
  it("leaves the stock installation unchanged", () => {
    expect(edgeListeners({})).toEqual({ behindProxy: false, http: 80, https: 443, address: "" });
  });
  it.each(["0", "80", "443", "-1", "65536", "9080;", "9145", "49180", "09080"])("rejects unsafe port %s", (port) => {
    expect(() => edgeListeners({ OPENSHIP_EDGE_BEHIND_PROXY: "true", OPENSHIP_EDGE_HTTP_PORT: port })).toThrow();
  });
  it("rejects a shared HTTP/HTTPS port", () => {
    expect(() => edgeListeners({ OPENSHIP_EDGE_BEHIND_PROXY: "true", OPENSHIP_EDGE_HTTP_PORT: "9443" })).toThrow();
  });
  it("moves both baked catch-alls to loopback without altering management or upstreams", () => {
    vi.stubEnv("OPENSHIP_EDGE_BEHIND_PROXY", "true");
    const output = edgeListenerConfig(bakedEdgeNginxConf());
    expect(output).toContain("listen 127.0.0.1:9080 default_server;");
    expect(output).toContain("listen 127.0.0.1:9443 ssl default_server;");
    expect(output).not.toMatch(/listen (80|443)[ ;]/);
    expect(output).toContain("127.0.0.1:49180");
    expect(edgeListenerConfig(output)).toBe(output);
  });
});
