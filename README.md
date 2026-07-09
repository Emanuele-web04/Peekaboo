# Peekaboo

A tiny native macOS to-do list that stays out of the way until you need it.

Peekaboo lives in the menu bar and reveals a lightweight panel when the pointer rests in a chosen screen corner. It is built with SwiftUI, AppKit and SwiftData, with no account or cloud service required.

## Demo

![Peekaboo showing In Progress and To do tasks](Media/peekaboo-fullscreen-preview.png)

## Features

- Reveals from any screen corner after a configurable delay
- Global `Control–Option–Space` shortcut for creating a task
- Separate Tasks and Backlog scopes, with To do, In Progress and Done states
- None, Low, Medium and High priorities
- Local SwiftData persistence
- Automatic cleanup of completed tasks after the day changes
- Multi-display and full-screen Space support
- Configurable reveal and hide delays
- Optional translucent or solid panel
- Launch at login support
- Native menu bar app with no Dock icon
- Event-driven UI and low-overhead pointer sampling

## Requirements

- macOS 14 or newer
- Xcode 16 or newer

## Build and run

1. Clone the repository.
2. Open `Peekaboo.xcodeproj` in Xcode.
3. Select the `Peekaboo` target and choose your development team under Signing & Capabilities.
4. Change the bundle identifier if your Apple developer account does not own `com.emanueledipietro.Peekaboo`.
5. Run the app.

Choose a corner and reveal delay in Settings. Press `Control–Option–Space` from anywhere in macOS to reveal Peekaboo with the new-task field focused.
Press `Command–,` while Peekaboo is focused to open Settings.

## Interactions

- Double-click a To do task to move it to In Progress.
- Double-click an In Progress task to move it back to To do.
- Click or double-click a Backlog idea to promote it to To do.
- Click the priority-colored circle to complete a task.
- Click the circle on a completed task to restore it.
- Drag tasks to reorder them within the same status and priority group.
- Drag a task into another app to insert its title as plain text.
- Use the trailing ellipsis to edit, move, reprioritize or delete a task.

## Tests

```sh
xcodebuild test \
  -project Peekaboo.xcodeproj \
  -scheme Peekaboo \
  -destination 'platform=macOS'
```

## Project generation

`Scripts/generate_project.rb` atomically generates the Xcode project using the Ruby `xcodeproj` gem and stable UUIDs. Run it after adding source files that need to be included in the project. Use `--help` to inspect the command without changing the project, or `--output PATH` to generate a separate copy.

Run `ruby Scripts/verify_project_generation.rb` to confirm that two consecutive generations are identical.

## License

Peekaboo is available under the [MIT License](LICENSE).
