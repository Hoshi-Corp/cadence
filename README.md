# Cadence

A macOS menu bar app for Pomodoro focus sessions, wellness reminders and a
daily Markdown work log.

## Requirements

- macOS 14+
- Xcode (license accepted: `sudo xcodebuild -license accept`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

The Xcode project is generated from `project.yml` and not committed.

## Build & run

```sh
make test      # run unit tests
make run       # build Release and launch from build/
make install   # build, copy to /Applications and launch
make open      # open the generated project in Xcode
```

The Makefile uses `/Applications/Xcode.app` via `DEVELOPER_DIR`, so there's
no need to `xcode-select` it. Use `make install` if you want *Launch at login*:
macOS registers login items most reliably from `/Applications`.

## Signing

Builds are ad-hoc signed by default, which needs no Apple account. That's fine
for v0.1, which only asks for notification permission.

Activity tracking (planned) needs the Accessibility permission, which macOS
ties to the code signature. With ad-hoc signing you'd have to grant it again
after every rebuild. To avoid that, on each Mac:

1. Xcode → Settings → Accounts → add your (free) Apple ID. Xcode creates an
   *Apple Development* certificate.
2. Create `Config/Signing.local.xcconfig` (git-ignored):

   ```
   CADENCE_SIGN_IDENTITY = Apple Development
   CADENCE_TEAM = <your team ID, shown in Xcode's Accounts pane>
   CODE_SIGN_STYLE = Automatic
   ```

## Work log format

One file per day, named `yyyy-MM-dd.md`, in the folder chosen in
Settings → Work Log (default `~/Documents/Cadence`). The naming matches
Obsidian's Daily Notes, so the folder can live inside a vault.

Cadence only edits content between its own markers, which are invisible when
rendered:

```markdown
<!-- cadence:timeline:start -->
## Timeline

- **09:05–09:30** 🍅 Refactor auth module — *extracted token service*
- **10:15** Standup with team
- **10:45** 💧 Drink water
<!-- cadence:timeline:end -->
```

- Timeline entries are only ever **appended**, so edits you make to existing
  lines are kept.
- The **Summary** block is regenerated on every write from per-day counters
  kept in `~/Library/Application Support/Cadence/stats/`.
- Text outside the markers is never touched. If a daily note already exists,
  the blocks are appended to it.

## Layout

```
Cadence/
  App/          entry point, AppState (wires everything together)
  Pomodoro/     PomodoroEngine state machine
  Reminders/    Reminder model, ReminderScheduler (holds reminders during focus)
  WorkLog/      Markdown document ops, entries, stats, file store
  Preferences/  Codable preferences persisted to UserDefaults
  System/       notifications, launch at login
  UI/           menu bar popover and Settings window
CadenceTests/   Swift Testing unit tests
```
