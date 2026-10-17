# wow-addons

This repo is rooted at `World of Warcraft/_retail_/Interface/AddOns`. The folder
also holds Blizzard and third-party addons that this repo doesn't own. `.gitignore`
ignores everything (`/*`) and then lists the addons we maintain.

## Tracked addons

- `CastBarOnly/`: hides target/focus frame elements except the cast bar
- `DebugConsole/`: `/dbg <lua>` runs a snippet and shows the output in a copyable
  window (see below)
- `OrderScout/`: colors crafting order rows by the cost of the reagents you'd
  supply, using vendor and AH prices it records as you browse

To start tracking another addon, add `!/AddonName/` to `.gitignore` and list it above.

## Git workflow

These addons are personal-use, with a single user. For work on the live game, commit
and push straight to `main`. No branches or PRs are needed.

The exception is PTR or beta work, such as preparing for an upcoming API change.
Do that on a branch so `main` keeps matching the live client.

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

The DebugConsole addon provides the command for this: `/dbg <lua>`. It runs the
code with `loadstring` + `pcall`, captures everything passed to `print`, and shows
the code, output, any return value, and any errors in a modal with copyable text
(Ctrl+A, Ctrl+C).

When writing snippets for the user:

- Keep each snippet to **one line** that fits in the chat box (about 255
  characters). Use `;` between statements and avoid long string literals. For
  longer probes, add a temporary helper function to the addon and call that.
- Use `print(...)` for output. Return values are shown as well.
- Check for nil before indexing frames or globals, so a missing frame reports
  `nil` instead of throwing an error.

- Snippets run in the global environment, so they can't see an addon's `local`s
  or its private `ns` table. If a probe needs that state, expose it through a
  global, for example `_G.MyAddon = ns`.

Other addons shouldn't build their own debug commands. When an addon needs a
multi-line report, like CastBarOnly's `/cb list [target|focus]`, it should call
`DebugConsole.Show(text)`. Declare `## OptionalDeps: DebugConsole` in the `.toc`,
and fall back to `print` when `DebugConsole` isn't loaded.

## Notes

- Target the current retail API (see `## Interface:` in each `.toc`). The 12.0
  API notes at the top of `CastBarOnly.lua` record what has been learned so far.
- Changes take effect after `/reload` in game. New addons and new files
  added to a `.toc` need a full client restart.
