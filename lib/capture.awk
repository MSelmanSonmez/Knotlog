# quipu — capture layer: turn one tool-use event (single JSON line) into
# zero or more EVENT<TAB>TOOL<TAB>PATH rows for activity.log.
# Loaded alongside jsonfield.awk (awk -f lib/jsonfield.awk -f lib/capture.awk).
#
# Dispatch is payload-shaped, not tool-name-shaped (FAZ 4, K-1):
#   * tool_input.file_path present  -> one row, unchanged (Claude Code schema)
#   * no file_path, tool_name = apply_patch -> one row per affected path in
#     Codex's native *** Add/Update/Delete File envelope. A move records both
#     its source and destination. Legacy "+++ b/" unified-diff targets remain
#     accepted; legacy "/dev/null" targets remain dropped.
#   * otherwise -> no rows.
#
# No literal backslash anywhere in this file (PLAN 4.11): control bytes come
# from code points via the jsonfield helpers (q_, bs_, tab_, cr_, nl_).
# No regex: the diff scan uses substr only (PLAN 4.8).
BEGIN { OFS = sprintf("%c", 9) }
{
  ev = jsonfield($0, "hook_event_name")
  tool = jsonfield($0, "tool_name")
  p = jsonfield_scoped($0, "tool_input", "file_path")
  # Windsurf / Devin post_write_code: path in tool_info, event named by agent_action_name.
  if (p == "" && tool == "") {
    p = jsonfield_scoped($0, "tool_info", "file_path")
    if (p != "") { tool = "Write"; ev = jsonfield($0, "agent_action_name") }
  }
  # Cursor afterFileEdit has no tool_name and carries file_path at the top level.
  # Fall back only when tool_name is absent, so Claude and Codex payloads never
  # reach it; the tool is named Write, the value Cursor's matcher uses for edits.
  if (p == "" && tool == "") {
    p = jsonfield($0, "file_path")
    if (p != "") tool = "Write"
  }
  if (p != "") {
    # Contract 8: no TAB/CR/LF may reach the log.
    gsub(tab_(), "", p)
    gsub(cr_(), "", p)
    gsub(nl_(), "", p)
    if (ev != "" && tool != "" && p != "") {
      print ev, tool, p
    }
    exit
  }
  # file_path absent: apply_patch carries paths in its command text. Current
  # Codex uses an explicit patch envelope. Parse only header lines between its
  # begin/end markers so patch content that resembles a header cannot inject a
  # log row. Each affected path is emitted once. For moves, the preceding
  # Update File emits the source and Move to emits the destination.
  if (tool == "apply_patch") {
    cmd = jsonfield_scoped($0, "tool_input", "command")
    if (cmd != "") {
      n = split(cmd, lines, nl_())
      inpatch = 0; native = 0; complete = 0; path_count = 0
      for (i = 1; i <= n; i++) {
        line = lines[i]
        if (line == "*** Begin Patch") { inpatch = 1; native = 1; continue }
        if (line == "*** End Patch" && inpatch) { inpatch = 0; complete = 1; continue }
        if (!inpatch) continue
        path = ""
        if (substr(line, 1, 14) == "*** Add File: ") path = substr(line, 15)
        else if (substr(line, 1, 17) == "*** Update File: ") path = substr(line, 18)
        else if (substr(line, 1, 17) == "*** Delete File: ") path = substr(line, 18)
        else if (substr(line, 1, 13) == "*** Move to: ") path = substr(line, 14)
        emit_path(ev, path, seen)
      }
      # A native envelope is valid only when both sentinels were present. This
      # also prevents a truncated QUIPU_MAX_STDIN prefix from producing rows.
      if (native && complete) flush_paths(ev)
      # Backwards compatibility for older/synthetic Codex payloads. Only
      # target headers are accepted, exactly as before.
      if (!native) {
        path_count = 0
        for (i = 1; i <= n; i++) {
          line = lines[i]
          if (substr(line, 1, 6) == "+++ b/") {
            path = substr(line, 7)
            if (path == "/dev/null") continue
            emit_path(ev, path, seen)
          }
        }
        flush_paths(ev)
      }
    }
  }
  exit
}

function emit_path(ev, path, seen,   key) {
  gsub(tab_(), "", path)
  gsub(cr_(), "", path)
  gsub(nl_(), "", path)
  while (substr(path, 1, 2) == "." "/") path = substr(path, 3)
  if (path == "" || path == "/dev/null") return
  key = path
  if ((key in seen) && seen[key] == NR) return
  seen[key] = NR
  path_rows[++path_count] = path
}

function flush_paths(ev,   i) {
  for (i = 1; i <= path_count; i++) print ev, "apply_patch", path_rows[i]
}
