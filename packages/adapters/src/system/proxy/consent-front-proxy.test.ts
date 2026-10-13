import { afterEach, expect, it, vi } from "vitest";
import type { CommandExecutor } from "../../types";

vi.mock("./detect", async (original) => ({
  ...await original<typeof import("./detect")>(),
  probeEdge: vi.fn(async () => ({
    classification: "known",
    occupants: [{ port: 9080, proxy: "apache", systemdUnit: "apache2.service" }],
    canProceedClean: false,
  })),
}));

import { ensureEdgeClear } from "./consent";

afterEach(() => vi.unstubAllEnvs());

it("never honours a takeover policy against an occupied internal port", async () => {
  vi.stubEnv("OPENSHIP_EDGE_BEHIND_PROXY", "true");
  const exec = vi.fn();
  await expect(ensureEdgeClear(
    { exec } as unknown as CommandExecutor,
    { edgePolicy: { mode: "takeover", stopTargets: [] } },
    vi.fn(),
  )).rejects.toThrow("front-proxy mode never takes over another service");
  expect(exec).not.toHaveBeenCalled();
});
