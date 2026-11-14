# knotlog - user prompt text from one prompt-hook payload (stdin).
# Loaded alongside jsonfield.awk. Prints the "prompt" field (Claude Code and
# Codex UserPromptSubmit, Gemini BeforeAgent all name it so), or nothing when
# the payload has none or is not JSON. No regex, no literal backslash.
{ s = s $0 }
END { printf "%s", jsonfield(s, "prompt") }
