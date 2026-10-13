/** Opt-in, installation-wide listeners for an edge behind a local TLS/auth proxy. */
export function edgeListeners(env: Record<string, string | undefined> = process.env) {
  if (env.OPENSHIP_EDGE_BEHIND_PROXY && !["true", "false"].includes(env.OPENSHIP_EDGE_BEHIND_PROXY)) {
    throw new Error("OPENSHIP_EDGE_BEHIND_PROXY must be true or false");
  }
  const behindProxy = env.OPENSHIP_EDGE_BEHIND_PROXY === "true";
  if (!behindProxy) return { behindProxy, http: 80, https: 443, address: "" };
  const port = (name: string, fallback: number) => {
    const value = env[name] || String(fallback);
    if (!/^[1-9][0-9]*$/.test(value) || Number(value) < 1024 || Number(value) > 65535) {
      throw new Error(`${name} must be an integer between 1024 and 65535`);
    }
    return Number(value);
  };
  const http = port("OPENSHIP_EDGE_HTTP_PORT", 9080);
  const https = port("OPENSHIP_EDGE_HTTPS_PORT", 9443);
  if (http === https || [http, https].some((p) => [9145, 49180].includes(p))) {
    throw new Error("Edge ports must differ and must not use management/ACME ports 9145 or 49180");
  }
  return { behindProxy, http, https, address: "127.0.0.1:" };
}

/** Apply only to generated Nginx configuration, never route JSON or certificate data. */
export function edgeListenerConfig(content: string): string {
  const settings = edgeListeners();
  if (!settings.behindProxy) return content;
  return content.replace(/^(\s*listen\s+)(?:80|443)(?=[\s;])([^;]*);/gm,
    (_, prefix: string, options: string) =>
      `${prefix}${settings.address}${/\bssl\b/.test(options) ? settings.https : settings.http}${options};`)
    .replace("real_ip_header CF-Connecting-IP;", "real_ip_header X-Forwarded-For;\n    set_real_ip_from 127.0.0.1;");
}
