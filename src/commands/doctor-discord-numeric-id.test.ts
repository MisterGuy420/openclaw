import { describe, expect, it } from "vitest";
import { scanDiscordNumericIds, type DiscordNumericIdHit } from "./doctor-config-flow.js";

describe("scanDiscordNumericIds", () => {
  it("detects numeric IDs in Discord allowFrom config", () => {
    const parsed = {
      channels: {
        discord: {
          allowFrom: [123456789012345678, "233734246190153728"],
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);

    // Should detect the numeric allowFrom ID
    expect(hits.length).toBeGreaterThanOrEqual(1);
    expect(hits[0].path).toContain("allowFrom");
    expect(typeof hits[0].value).toBe("number");
  });

  it("does not flag string IDs in Discord config", () => {
    const parsed = {
      channels: {
        discord: {
          users: ["233734246190153728", "987654321098765432"],
          roles: ["123456789012345678"],
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);
    expect(hits).toEqual([]);
  });

  it("detects numeric IDs in Discord guild config", () => {
    const parsed = {
      channels: {
        discord: {
          guilds: {
            "123456789012345678": {
              users: [233734246190153728], // Numeric ID - should be detected
              roles: ["987654321098765432"], // String ID - should NOT be detected
            },
          },
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);
    expect(hits.length).toBe(1);
    expect(hits[0].path).toContain("guilds");
    expect(hits[0].path).toContain("users");
  });

  it("detects numeric IDs in Discord execApprovals.approvers", () => {
    const parsed = {
      channels: {
        discord: {
          execApprovals: {
            approvers: [233734246190153728], // Numeric ID - should be detected
          },
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);
    expect(hits.length).toBe(1);
    expect(hits[0].path).toContain("approvers");
  });

  it("detects numeric IDs in Discord account config", () => {
    const parsed = {
      channels: {
        discord: {
          accounts: {
            work: {
              allowFrom: [233734246190153728], // Numeric ID - should be detected
              guilds: {
                "123456789": {
                  users: [987654321098765432], // Numeric ID - should be detected
                },
              },
            },
          },
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);
    expect(hits.length).toBe(2);
    expect(hits.some((h) => h.path.includes("allowFrom"))).toBe(true);
    expect(hits.some((h) => h.path.includes("users"))).toBe(true);
  });

  it("returns empty array when Discord config is missing", () => {
    const parsed = {
      channels: {
        telegram: {
          allowFrom: ["123"],
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);
    expect(hits).toEqual([]);
  });

  it("handles null and undefined gracefully", () => {
    expect(scanDiscordNumericIds(null)).toEqual([]);
    expect(scanDiscordNumericIds(undefined)).toEqual([]);
    expect(scanDiscordNumericIds({})).toEqual([]);
    expect(scanDiscordNumericIds([])).toEqual([]);
  });

  it("detects numeric IDs in Discord dm.allowFrom", () => {
    const parsed = {
      channels: {
        discord: {
          dm: {
            allowFrom: [233734246190153728], // Numeric ID - should be detected
          },
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);
    expect(hits.length).toBe(1);
    expect(hits[0].path).toContain("dm.allowFrom");
  });

  it("detects numeric IDs in Discord guild channel config", () => {
    const parsed = {
      channels: {
        discord: {
          guilds: {
            "123456789": {
              channels: {
                "987654321": {
                  users: [233734246190153728], // Numeric ID - should be detected
                  roles: [987654321098765432], // Numeric ID - should be detected
                },
              },
            },
          },
        },
      },
    };

    const hits = scanDiscordNumericIds(parsed);
    expect(hits.length).toBe(2);
    expect(hits.some((h) => h.path.includes("users"))).toBe(true);
    expect(hits.some((h) => h.path.includes("roles"))).toBe(true);
  });
});
