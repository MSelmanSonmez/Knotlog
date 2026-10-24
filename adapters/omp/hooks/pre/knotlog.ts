import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";

export default function knotlogHook(pi: HookAPI) {
  pi.on("session_start", async (_event, ctx) => {
    try {
      await pi.exec("knotlog", ["remember"], { cwd: ctx.cwd });
      const result = await pi.exec(
        "knotlog",
        ["context", "--json", "SessionStart"],
        { cwd: ctx.cwd },
      );
      const parsed = JSON.parse(result.stdout);
      const text = parsed?.hookSpecificOutput?.additionalContext;
      if (!text) return;
      pi.sendMessage(
        { customType: "knotlog-context", content: text, display: false },
        { triggerTurn: false },
      );
    } catch (err) {
      pi.logger.warn("knotlog session_start hook failed", { error: String(err) });
    }
  });

  pi.on("agent_end", async (_event, ctx) => {
    try {
      const result = await pi.exec(
        "knotlog",
        ["context", "--json", "Stop"],
        { cwd: ctx.cwd, timeout: 10000 },
      );
      const stdout = result?.stdout?.trim();
      if (!stdout) return;
      const parsed = JSON.parse(stdout);
      if (parsed?.decision === "block" && parsed?.reason) {
        pi.sendMessage(
          { customType: "knotlog-checkpoint", content: parsed.reason, display: false },
          { triggerTurn: false },
        );
      }
    } catch (err) {
      pi.logger.warn("knotlog agent_end hook failed", { error: String(err) });
    }
  });
}
