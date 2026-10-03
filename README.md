# GRIT

## Current preview — v0.13

Latest fixes include five-second dismissible feedback, safe Undo after newer edits, improved Schedule drag-and-drop, and snooze clearing when scheduling. Selected-day planning now keeps Tomorrow tasks, summaries and capture dates consistent across Schedule and Calendar. All 79 Flutter tests pass and static analysis is clean. See [verification](docs/VERIFICATION.md) for tested behavior and release limitations.

Collapsing iOS-style titles, native phone tab navigation, draggable task sheets, action-sheet pickers, task swipes, spring motion, haptics and System/Light/Dark/OLED appearance. iOS Today widget extension and durable completion bridge source are included; Xcode/device verification is pending. See [docs/PART-C.md](docs/PART-C.md) and [docs/IOS-SETUP.md](docs/IOS-SETUP.md).

The earlier typed custom fields, richer Board cards, project completion rings, density options, persisted focus time and opt-in gamification remain. AI is skipped. See [docs/PART-B.md](docs/PART-B.md).

**Cloud status in 0.4:** Authentication can be configured, but sync stays local until the new revocation-checking Functions and hardened rules are deployed. SECURE_SYNC_ENABLED defaults off. Older owner-only rules remain live. The cloud-sync descriptions below are historical 0.3 behavior, not active 0.4 sync. Backend deployment requires owner billing setup; no paid service was activated.

A responsive Flutter personal planner with a calm task-first interface, adaptive navigation and light/dark themes. Full Todoist parity and production multi-user services remain unfinished.

## Run the correct project

This folder contains pubspec.yaml. Run Flutter commands here, rather than in the parent workspace:

```powershell
git clone https://github.com/Logesh-Murugan/grit.git
cd grit
flutter pub get
flutter run -d chrome
```

To build and serve a local web preview:

```powershell
flutter build web --release
node preview.cjs
```

Open http://127.0.0.1:4173/ and keep the server running. Compiled builds and private Firebase configuration are excluded from this repository. For Firebase setup, copy firebase.example.json to firebase.local.json, fill your project's configuration, and pass --dart-define-from-file=firebase.local.json to Flutter. See docs/SETUP-SERVICES.md.

Run checks with flutter analyze and flutter test.

Use ?preview=true for temporary sample data. Normal mode saves data locally on the browser origin; changing port/browser creates a separate local workspace.

## Earlier personal-planner features

Nested/reordered projects, filter favorites, saved project views, collapsible subtasks, bare-time quick capture, custom RRULE recurrence, local attachments, daily time-block grid with overlap checks, ICS export, weekly goals and goal streaks, drag-to-day Upcoming scheduling, and tested Other… creation in both category and project pickers.

Personal workspace records have a durable outbox. Android widget, notification quick-add, Quick Settings tile and text share capture source are supplied; Android remains uncompiled here.

## Scope and verification

See docs/FEATURE-MATRIX.md for each requested feature, docs/VERIFICATION.md for actual checks, docs/RELEASE-GAPS.md for unfinished release work, and docs/SETUP-SERVICES.md for owner setup.

Authentication requires Firebase defines. This workspace has an ignored firebase.local.json for grit-4da5a. Secure cloud sync additionally requires Functions/hardened-rules deployment and SECURE_SYNC_ENABLED=true. Google/Outlook two-way sync and shared projects are not implemented. Android code has not been compiled or device-tested because the SDK is absent. No APK, AAB, public hosting or Play Store release exists.

Attachments stay device-local (1 MB per file, 2 MB combined and five per task). Keep JSON backups. After deployment, checked server polling uses last-write-wins for simultaneous edits to one record. Live revocation and replay checks remain required before real users.
