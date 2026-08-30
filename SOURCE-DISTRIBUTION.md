# FreePlayer Source Distribution

This archive contains the current working source, including the managed `fpmlib` library plugin and the diagnostics logging plugin.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools (Swift, Clang, CMake, and Ninja)
- Node.js 20 or newer and pnpm 11

## Build

```sh
pnpm install
pnpm test
pnpm run build
pnpm run bundle
```

The generated app is `shell/build/FreePlayer.app`.

## Managed library

The managed library plugin is enabled by default. It stores imported audio and artwork in a single local `FreePlayer.fpmlib` container. Disable the plugin in the Plugins page to use the legacy filesystem import mode. The container is recreated by the database reset action when managed mode is enabled.

## Diagnostics

The diagnostics plugin can be enabled from the Plugins page. The persistent log is always written to:

`~/Library/Application Support/FreePlayer/diagnostics/freeplayer-diagnostics.log`

The in-app diagnostics panel shows the exact absolute path and offers a copy action. Logging can also be enabled for a launch with `FP_DIAGNOSTICS_ENABLED=1`.

## Source layout

- `src/`: React/Vite frontend and built-in plugins
- `shell/Sources/Core/`: database, metadata, and `fpmlib` container code
- `shell/Sources/Bridge/`: WebKit bridge and import pipeline
- `shell/Sources/UI/`: macOS UI integration, URL scheme handling, and diagnostics
- `scripts/`: development, build, bundle, and packaging scripts

