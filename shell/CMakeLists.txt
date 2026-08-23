cmake_minimum_required(VERSION 3.28)
# Must precede project(): CMake probes the Swift compiler inside project(),
# and without a deployment target it defaults to the host macOS version
# (e.g. macosx26.0 on macos-26 runners), which the toolchain's stdlib does
# not ship — "unable to load standard library for target 'arm64-apple-macosx26.0'".
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0")
project(FreePlayerShell LANGUAGES Swift)

set(CMAKE_Swift_FLAGS "-Osize")

# Modules are plain directories; Swift access control (internal/fileprivate)
# keeps the boundaries honest without extra framework targets.
set(SWIFT_SOURCES
  Sources/main.swift
  Sources/App/NavGate.swift
  Sources/Core/Database.swift
  Sources/Core/Metadata.swift
  Sources/Core/Paths.swift
  Sources/Bridge/BridgeScript.swift
  Sources/Bridge/BridgeHandler.swift
  Sources/Bridge/BridgeRouter.swift
  Sources/Bridge/HttpClient.swift
  Sources/Bridge/ImportPipeline.swift
  Sources/UI/AppContext.swift
  Sources/UI/SchemeHandler.swift
  Sources/UI/PlatformBridge.swift
  Sources/Platform/macOS/AppDelegate.swift
  Sources/Platform/macOS/Windows.swift
  Sources/Platform/macOS/Tray.swift
  Sources/Platform/macOS/PluginFS.swift
  Sources/Platform/macOS/MacPlatformBridge.swift
)

add_executable(FreePlayerShell ${SWIFT_SOURCES})
set_target_properties(FreePlayerShell PROPERTIES
  OUTPUT_NAME FreePlayerShell
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)

target_link_libraries(FreePlayerShell
  "-framework Cocoa"
  "-framework WebKit"
  "-framework AVFoundation"
  "-framework CoreMedia"
  "-framework AudioToolbox"
  "-framework MediaPlayer"
  "-framework ServiceManagement"
  "-framework UserNotifications"
  "-framework UniformTypeIdentifiers"
  "-lsqlite3"
)

# ── port of the Makefile targets ────────────────────────────────────────────

# make logo — regenerate icon rasters from assets/logo.svg (needs node + resvg)
add_custom_target(logo
  COMMAND node scripts/icons.mjs
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/..
  COMMENT "regenerating FreePlayer-1024.png + FreePlayer.icns"
)

# make bundle — dist + FreePlayer.app into build/FreePlayer.app
add_custom_target(bundle
  COMMAND bash scripts/bundle.sh
  DEPENDS FreePlayerShell
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/..
  COMMENT "bundling FreePlayer.app"
)

# make run / run-app
add_custom_target(run
  COMMAND ${CMAKE_BINARY_DIR}/FreePlayerShell
  DEPENDS FreePlayerShell
)

# make clean
add_custom_target(clean-all
  COMMAND ${CMAKE_COMMAND} -E rm -rf ${CMAKE_BINARY_DIR}
  COMMENT "removing cmake build dir"
)