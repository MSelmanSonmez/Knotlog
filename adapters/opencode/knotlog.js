// Knotlog plugin for OpenCode: capture edited files, remember + index when a session goes idle.
// Context reaches the model through AGENTS.md (OpenCode reads it natively); this plugin only records.
export const Knotlog = async ({ $, directory }) => {
  const run = (args) =>
    $`knotlog ${args}`.cwd(directory).env({ ...process.env, KNOTLOG_HOOK: "1" }).quiet().nothrow()
  return {
    event: async ({ event }) => {
      try {
        if (event.type === "file.edited") {
          // properties.file is unverified against a live OpenCode; guarded.
          const file = event.properties?.file ?? event.properties?.path
          if (file) await run(["capture", "--event", "file.edited", "--tool", "Write", "--path", String(file)])
        } else if (event.type === "session.idle") {
          await run(["remember"])
          await run(["index"])
        }
      } catch (_) {}
    },
  }
}
