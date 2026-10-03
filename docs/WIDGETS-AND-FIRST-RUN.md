# Today widgets and first-run polish — preview 0.10

## Native Today widget

The iOS 17+ WidgetKit extension supports small, medium and large sizes, system type and appearance, 44-point completion controls, privacy-sensitive task titles and count/overflow copy. A midnight timeline entry clears yesterday’s actions and prompts opening GRIT to refresh the next day. The gallery uses an intentional sample task. Actual task actions carry workspace and scheduled-occurrence identifiers so an old widget cannot complete a task from a different workspace or later recurrence.

Android now has separate completion controls for each visible row, 48dp touch targets, system-scaled text, day/night colors, a remaining-task count and quick-add. Short resized widgets show two tasks; taller widgets show three. Android uses an immutable explicit PendingIntent to a non-exported receiver. Snapshot writes and completion actions share a synchronized durable queue; a successful disk commit precedes removal from the widget.

Both platforms show open parent tasks scheduled today or overdue, pinned today and habits; completed, trashed, snoozed, archived-project and child tasks are excluded. Completion removes the visible row and queues an action locally. The app replays it on foreground and periodically while open, saves its workspace before acknowledgement, and ignores obsolete scheduled occurrences. Duplicate replay does not reopen or double-complete a task. Actions from another workspace remain untouched. Cloud propagation requires opening the app and the separately configured secure backend.

These are native implementations, not browser widgets. Neither Swift nor Kotlin has been compiled here. iOS requires a Mac/Xcode, signing and the App Group setup in IOS-SETUP.md. Android requires an Android SDK and launcher/device acceptance. No APK/IPA or installable widget release is supplied.

### Device acceptance

1. Save a task scheduled today, add Today in GRIT to the home screen and confirm the row appears.
2. Close the app. Tap a completion control. Confirm just that row disappears; reopen GRIT and confirm one completion.
3. Repeat offline, after process termination, with a recurring task, habit and multiple widgets. Change accounts and reschedule a task before tapping an old rendered widget.
4. Check before/after midnight, timezone changes, DST, storage failures, large font sizes, VoiceOver/TalkBack, dark/tinted appearance and widget resizing.
5. iOS: long-press the Home Screen, use the system Add Widget flow and choose Today in GRIT. Android: long-press the Home Screen, choose Widgets, find GRIT and place Today.

## First-run and empty-state review

Onboarding keeps one primary action and an optional sample-workspace action. Name is explicitly optional. Planning capacity is described as an adjustable gentle limit, and storage copy explains local data and backups without promising cloud sync.

A shared empty-state surface uses semantic headings, distinct contextual icons, centered readable text and clear actions. Body text inherits accessibility scaling. Actions open the actual flow:

| Surface | Message / next step |
| --- | --- |
| Today | Space in the day; Plan a task opens capture with today selected |
| Inbox | Capture a task now, organize later |
| Project list | Add first task in the current project |
| Calendar date | Add a task for the selected day |
| Search | Explicit no-match explanation; no blank results panel |
| Filter / label | Explain matching tasks without implying other tasks are gone |
| Habits | Create a habit opens capture with Habit preselected |
| Milestones | Add a milestone opens its editor |
| Activity / Completed | Explain future records and offer Go to Today |
| Trash | Explain recovery, without prompting a task creation |
| Reminders | Explain where reminders appear and offer capture; open-app-only delivery remains explicit |
| Board / Upcoming | Existing column/day headers and contextual Add actions remain; drag targets stay available when empty |
| Labels | Existing label guidance and Manage labels action remain |

Preview-only review URLs use temporary data and do not replace saved local data:
- `http://127.0.0.1:4180/?preview=true&version=10&screen=welcome`
- `http://127.0.0.1:4180/?preview=true&version=10&screen=empty`
- Normal sample: `http://127.0.0.1:4180/?preview=true&version=10`

## Validation

71 Flutter tests pass, including native completion replay tests on both platform variants, Today snapshot selection, parent/snooze exclusion, first-task capture from an empty screen, 3x empty-state text in Light and OLED, and the existing onboarding/accessibility checks. Analysis is clean. Android XML and iOS plist/entitlement syntax were parsed successfully. Native compilation, launcher/WidgetKit interaction and real VoiceOver/TalkBack acceptance are pending, not implied by Flutter tests.

Implementation references: [Apple interactive widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) and [Android RemoteViews](https://developer.android.com/reference/android/widget/RemoteViews).
