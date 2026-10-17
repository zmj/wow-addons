# wow-addons

This repo is rooted at `World of Warcraft/_retail_/Interface/AddOns`. The folder
also holds Blizzard and third-party addons that this repo doesn't own. `.gitignore`
ignores everything (`/*`) and then lists the addons we maintain.

## Tracked addons

- `CastBarOnly/`: hides target/focus frame elements except the cast bar

To start tracking another addon, add `!/AddonName/` to `.gitignore` and list it above.

## Editing rules

- **Read anything.** All addons in this folder can be used as reference: our own,
  third-party (e.g. IceHUD, totalRP3, Simulationcraft), and Blizzard_*. They're
  useful for finding API usage, frame names, and patterns.
- **Edit only tracked addons.** Make lasting changes only in the addons listed above.
- **Temporary debugging edits elsewhere are OK**, such as adding a `print` to a
  third-party addon to trace a problem. Say what you changed, and revert it when
  you're done. Those addons aren't under version control here, so git won't catch
  edits that are left behind.

## In-game debug loop

Code is tested in the live game client, which Claude can't run. The workflow that
has worked best:

1. Claude writes a Lua snippet that inspects the state in question.
2. The user runs it in game and pastes the output back.
3. Repeat until the cause is clear, then edit the addon.

CastBarOnly has a slash command for this: `/cb dbg <lua>`. It runs the code with
`loadstring` + `pcall`, captures everything passed to `print`, and shows the code,
output, any return value, and any errors in a modal with copyable text
(Ctrl+A, Ctrl+C). `/cb list [target|focus]` dumps a frame's children and regions
the same way.

When writing snippets for the user:

- Keep each snippet to **one line** that fits in the chat box (about 255
  characters). Use `;` between statements and avoid long string literals. For
  longer probes, add a temporary helper function to the addon and call that.
- Use `print(...)` for output. Return values are shown as well.
- Check for nil before indexing frames or globals, so a missing frame reports
  `nil` instead of throwing an error.

New addons that need in-game investigation should get the same tool: a `dbg`
subcommand plus a copyable output modal. Copy the implementation from
`CastBarOnly.lua` (`CreateDebugModal` / `ExecuteDebugCode`).

## Notes

- Target the current retail API (see `## Interface:` in each `.toc`). The 12.0
  API notes at the top of `CastBarOnly.lua` record what has been learned so far.
- Changes take effect after `/reload` in game. New addons and new files
  added to a `.toc` need a full client restart.
