# Peekaboo Project Instructions

<!-- BEGIN PEEKABOO LIVE SYNC CONTRACT -->
## Live Sync Contract — Non-Negotiable

Peekaboo is a local-first SwiftData app whose Mac and iPhone targets synchronize
through the same private CloudKit database. Live two-way sync is a core product
feature, not an optional integration. Never merge, archive, upload, or install a
sync-related change unless every invariant and release check below remains true.

### Mandatory identifiers and environments

- Both targets MUST use bundle identifier `com.emanueledipietro.Peekaboo`.
- Both targets MUST use CloudKit container
  `iCloud.com.emanueledipietro.Peekaboo`.
- Release/TestFlight builds MUST use CloudKit `Production` and production APNs.
- Debug and Local builds MUST use CloudKit `Development` and development APNs.
- `ICLOUD_CONTAINER_ENVIRONMENT` and `APS_ENVIRONMENT` MUST always describe the
  same environment. Never mix Production CloudKit with development APNs.
- Development and Production MUST NOT share a SQLite store. Production uses the
  default SwiftData store; Development uses `development.store`.
- Never point a Debug/Local build at the Production store, and never install a
  development-signed archive as a substitute for the TestFlight Mac build when
  validating production sync.

### Mandatory macOS entitlements — do not remove

Every macOS configuration (`Peekaboo.entitlements`,
`PeekabooDebug.entitlements`, and `PeekabooLocal.entitlements`) MUST retain both
values under `com.apple.security.temporary-exception.mach-lookup.global-name`:

```text
com.apple.cloudd
com.apple.duetactivityscheduler
```

- `com.apple.cloudd` is required for the sandboxed app to reach CloudKit.
- `com.apple.duetactivityscheduler` is required for
  `NSPersistentCloudKitContainer` to schedule exports in the sandboxed
  TestFlight/Mac App Store build.
- These are NOT harmless log-suppression exceptions. Do not remove either one
  during cleanup, security review, entitlement minimization, or release prep.
- The Mac app MUST keep network client/server, CloudKit container, iCloud
  service, production/development APNs, and App Sandbox entitlements intact.
- App Store Connect MUST contain temporary-entitlement usage information for
  both Mach services and the corresponding Feedback Assistant ID.

Incident record: Mac build 8 removed `com.apple.duetactivityscheduler`. The app
continued saving tasks locally and CloudKit setup appeared successful, but no
new export was scheduled after a local save. Mac-to-iPhone sync stopped. Build 9
restored the entitlement. Never repeat this change.

### Persistence and observation invariants

- Keep `NSApplication.shared.registerForRemoteNotifications()` on macOS.
- Keep both `NSPersistentStoreRemoteChange` and
  `NSPersistentCloudKitContainer.eventChangedNotification` observation.
- On a completed CloudKit import, replace the long-lived `ModelContext` with a
  fresh context before fetching. A normal fetch on the cached context can keep
  stale values visible and can write them back over imported changes.
- Keep foreground, wake, day-change, time-zone-change, and panel-reveal refresh
  fallbacks. They may refresh local state; they are not a replacement for a
  functioning CloudKit import/export pipeline.
- Do not add aggressive polling. Sync and UI refresh MUST stay event-driven to
  avoid CPU spikes.
- SwiftData models used by CloudKit MUST remain CloudKit-compatible: properties
  need defaults or optionality, and app UUIDs MUST NOT use a SwiftData unique
  constraint that CloudKit cannot enforce.
- CloudKit can contain multiple physical records with the same app-level UUID.
  Deduplicate only for presentation. Never delete an arbitrary duplicate during
  refresh. Mutations and deletion MUST apply to every physical replica of the
  selected app UUID.
- Done-task cleanup MUST use `completedAt` relative to the start of the current
  local day. `updatedAt` must not keep a task completed on a previous day alive.
  A divergent duplicate must prevent destructive cleanup until replicas agree.
- Never delete, reset, migrate, or replace the user's production store or
  CloudKit container as a debugging shortcut without explicit user approval.

### Known failure signatures

Treat these as real failures until disproved:

- `BGSystemTaskSchedulerErrorDomain Code=3`, `updateTaskRequest failed`, or
  repeated `com.apple.coredata.cloudkit.activity.export...` scheduling errors.
  First verify the `com.apple.duetactivityscheduler` entitlement in the
  INSTALLED TestFlight app, not only in the source plist or development archive.
- Phone-to-phone sync works but Mac does not: inspect the installed Mac build,
  Production entitlements, active store path, CloudKit event timestamps, and
  fresh-context import refresh.
- A task appears in `default.store` but no later export event appears in
  `ANSCKEVENT`: the Mac mirroring/export scheduler is broken. UI refresh code
  cannot fix it.
- Import/export setup events succeed with zero objects, then no event follows a
  local mutation: do not report sync as healthy.
- Data exists in SQLite but not in the panel: inspect stale `ModelContext`
  handling and completed-import refresh before changing CloudKit configuration.
- Multiple installed/running Peekaboo copies can use different builds or
  environments. Confirm the exact executable with `pgrep -fl Peekaboo`, the
  bundle version, code signature, entitlements, and opened store before testing.

### Required verification after any sync, persistence, signing, or release change

Build success and unit tests are insufficient. Complete all of the following:

1. Regenerate `Peekaboo.xcodeproj` from `Scripts/generate_project.rb` and run
   `Scripts/verify_project_generation.rb`.
2. Inspect the archived AND installed app entitlements with `codesign`. Confirm
   Production CloudKit/APNs and both Mach lookup services in the TestFlight Mac
   app.
3. Confirm only the intended Peekaboo build is running and record its bundle
   version. Do not accidentally test DerivedData or an old `/Applications` copy.
4. Use real TestFlight builds on a real Mac and real iPhone signed into the same
   iCloud account. Simulator or development-only success does not prove
   Production live sync.
5. Mac → iPhone: create or edit a uniquely named task on Mac. Verify that a new
   CloudKit export event occurs after the mutation and that the change appears
   on iPhone without restarting either app.
6. iPhone → Mac: edit that task on iPhone. Verify a new import event and that the
   visible Mac panel updates without restarting or repeatedly clicking refresh.
7. Repeat with priority and status changes, including Done and restore, because
   field updates previously exposed stale-context behavior.
8. Delete the diagnostic task only after both directions pass, and verify that
   the deletion also synchronizes.

If any step fails, the release is blocked. Do not call sync fixed, do not upload
another replacement build, and do not modify entitlements speculatively. Capture
the installed entitlements, store path, latest CloudKit events, and exact
one-way failure before making the next change.

### Release discipline

- Increment the platform build number before every App Store Connect upload;
  uploaded build numbers cannot be reused.
- Keep the Xcode project generator as the source of truth for build numbers,
  environments, signing settings, targets, and shared sources.
- Deploy the SwiftData/CloudKit schema to Production before TestFlight builds
  depend on new fields.
- Upload Mac and iPhone independently and wait until each build is processed and
  assigned to the intended internal TestFlight group.
- Install the distributed TestFlight Mac build before validating sync. An
  archive signed for development can have different APNs behavior.
- Never “fix” CloudKit scheduler errors by suppressing logs or removing sandbox
  exceptions. Prove an export after a local save instead.

Keep this entire Live Sync Contract synchronized verbatim between the root
`AGENTS.md` and `claude.md`. Any deliberate change to these invariants requires
a written reason and a successful real-device two-way sync verification.
<!-- END PEEKABOO LIVE SYNC CONTRACT -->
