# Verification record — GRIT

## 0.5 (current)

59 Flutter tests passed; analysis has no issues; release web build succeeded. Native gesture, sheet drag-dismiss, accessibility scaling up to 3×, Reduce Motion, appearance persistence and widget completion replay checks are included. Xcode project syntax/target wiring/plists were validated separately; no iOS compilation or device testing was performed. The rebuilt 4180 preview was reviewed at 390×844; native Today navigation and task capture were visually checked. See [PART-C.md](PART-C.md).

## 0.4 (historical)

50 Flutter tests passed, analysis has no issues, release web build succeeded. Eight mocked server-policy tests and ten hardened Firestore rules emulator checks passed. Live password/MFA revocation and deployment remain unverified. See [PART-B.md](PART-B.md).

## 0.3 (historical)

Date: 2026-10-01

- Flutter static analysis: no issues.
- All 41 domain, planning and widget tests passed. Phone drawer navigation was corrected to actually hit each intended item; final run has no missed-tap warnings.
- Requested bare-time capture, stable recurrence anchors, finite RRULEs, nested project cycle prevention/reorder, time-block overlap/undo, ICS encoding/folding, custom categories/projects persistence and cloud-record attachment exclusion are covered.
- Category and project Other… menus visibly verified in the freshly compiled browser; local custom create/save/reload is covered by a widget test.
- Release web build succeeded, served successfully on port 4180. Local CanvasKit assets are bundled.
- Firestore emulator: 15 security checks passed with separate Alice/Bob/anonymous contexts. Owner access succeeds; cross-user/anonymous access, malformed envelopes, unknown types/collections, physical deletes and client subscription grants fail.
- Firebase owner project grit-4da5a and GRIT Web app registered. Console shows Email/Password and Google providers enabled. Public configuration is saved in ignored firebase.local.json.
- Firestore provisioned in asia-south1 (Mumbai), after retrying a temporary provisioning error. The emulator-tested owner-only rules were published with explicit user approval and verified after reload. Cloud replay and multi-device acceptance testing remain pending.
- Android SDK absent. Native widget/notification/tile/share/file bridge source has not been compiled, signed or device-tested.
- No APK/AAB, public hosting deployment or Play Store submission. Database rules were deployed; hosting was not.

The rules test is reproducible from backend/security-tests after npm install, using npm test and Java 21+. It uses demo-grit only, not the live Firebase project.

Known successful-build warning: missing Cupertino icon font during tree shaking; this app uses Material icons.

Full production parity remains unfinished; see FEATURE-MATRIX.md and RELEASE-GAPS.md.

## UI/UX preview 0.9 — October 3, 2026

- All 66 Flutter tests passed; static analysis reports no issues.
- Release web build succeeded with both Cupertino and Material icon assets bundled.
- Browser inspection at phone width verified Today, the independently scrolling task detail sheet, project overview/Board, and OLED appearance. The edit icon renders correctly and detail groups fill the sheet width.
- Completing a preview task updated the day totals; Undo restored the task and totals.
- `preview-today-v09.png`, `preview-details-v09.png`, and `preview-oled-v09.png` record the current phone surfaces.
- Automated checks cover 3x task-detail text scaling in Light, Dark and OLED, immediate completion haptic dispatch, spring collapse/Undo, and small colored-caption contrast.
- This is browser/widget-test validation. Physical iPhone haptics, VoiceOver, native compilation/signing and WidgetKit acceptance remain unverified; see PART-C.md and IOS-SETUP.md.
- Cloud security/backend deployment and production feature gaps remain open; the earlier October 1 owner-rule deployment does not establish the current secure-backend rollout.

## Widget and first-run preview 0.10 — October 3, 2026

71 Flutter tests pass and static analysis reports no issues. Native completion queues are tested through mocked platform channels for iOS and Android, including persistence before acknowledgement, duplicate replay, account isolation and scheduled-occurrence checks. Empty-state capture creates a task scheduled today. 3x empty-state layouts and existing onboarding checks pass. Native XML/plist syntax parses successfully. See WIDGETS-AND-FIRST-RUN.md for the review matrix and device acceptance limits.

The final release web build succeeded. Browser review verified first-run onboarding, Create my space leading to the empty Today view, a reachable Plan a task action, and explicit no-match search guidance. Phone screenshots: preview-onboarding-v10.png and preview-empty-today-v10.png. The redundant zero-task Today summary is hidden until tasks exist.

## Schedule drag fix — preview 0.11, October 3, 2026

Schedule chips previously required a long press for mouse input despite saying Drag. Existing schedule blocks were tap-only. Schedule now uses device-specific recognizers: mouse/stylus dragging starts immediately, touch waits 300ms so scrolling/tapping remains available. Existing blocks can move to another hour, highlighted hour targets stay reachable behind blocks during a drag, and edge scrolling reaches hours outside the viewport. Successful drops save both time-block and scheduled time, provide haptics and Undo; rejected overlaps display immediately.

73 Flutter tests pass. New regression tests cover immediate mouse dragging, touch hold, existing-block movement, overlap rejection, Undo, persisted times and phone viewport edge scrolling. Static analysis is clean and the release web build succeeds. A live browser mouse drag placed the research-proposal sample at 01:00. The local preview server now versions bootstrap/main script requests by build modification time to avoid an older Flutter service worker serving stale code. Normal workspace storage was not cleared.

Live browser verification also moved the same block from 01:00 to 03:00. preview-schedule-drag-v11.png records the result.


## Timed feedback and logic audit — preview 0.12, October 3, 2026

Transient task feedback now expires after five seconds, including action messages with accessible navigation enabled. Every notice has a close button, new feedback replaces the previous notice rather than building a queue, and navigation clears transient feedback. Reminder feedback retains its explicit 15-second duration. Timers are cancelled on disposal and replacement.

Undo actions capture a revision and cannot apply an older snapshot after a newer persisted edit. Undo snapshots are cleared when loading another workspace or receiving remote workspace changes. Explicit time-block scheduling clears snooze so the task can appear in Today.

77 Flutter tests pass, static analysis is clean, and the release web build succeeds. Regression coverage includes accessibility-enabled timeout, replacement timing, manual close, navigation-style dismissal, stale Undo after a newer edit, snooze clearing, mouse/touch drags, overlap rejection, edge scrolling and saved schedules. The full suite also covers capture parsing, recurrence, hierarchy, custom fields, focus tracking, backup validation, native widget bridge reconciliation, onboarding, responsive layouts and theme/accessibility checks. This is not a claim that every production feature or native platform is bug-free; previous cloud/native release limitations remain.

Live browser verification: dragged the sample research task to 01:00, observed Undo and Close, then verified both controls and the message disappeared automatically while the scheduled block remained. Screenshot: preview-notice-dismissed-v12.png.
