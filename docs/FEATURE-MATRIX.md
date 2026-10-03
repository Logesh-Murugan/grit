# GRIT 0.5 — feature status

See [PART-B.md](PART-B.md) for new custom fields, focus logs, density and gamification. AI is skipped. Secure cloud sync is disabled until Functions and hardened rules are deployed. The cloud descriptions below record earlier 0.3 behavior and are superseded by this notice.

This is implemented scope, not a claim of full Todoist parity.

| Requested workflow | Status and limits |
|---|---|
| Inbox / Today / Upcoming / Filters & Labels | Working personal navigation and saved filters |
| Nested projects / reorder / sections | Parent selection, cycle prevention, sidebar drag reordering, section groups |
| Favorites | Projects and saved filters |
| List / Board / Calendar | Working views, drag operations, per-project saved view |
| Natural capture | English dates, bare 5pm, p1–p4, #project and @labels; limited grammar with editable preview |
| Priorities / labels | Four colored priorities and cross-project labels |
| Subtasks | Nested, collapsible, recursive completion/restore/duplicate |
| Schedule vs. deadline | Separate dates; any explicit deadline can become overdue |
| Recurrence | Four presets and validated RRULE subset; unsupported clauses rejected |
| Comments / attachments | Local comments and file pick/download/remove; no cloud storage or mentions |
| Duration / time blocks | Estimates, daily Schedule grid, overlap checks and manual ICS export |
| Points / goals / trends | XP, daily/weekly goals, goal streak, rolling weekly chart and heatmap |
| Upcoming reschedule | Drag to days, including empty upcoming days |
| Shared projects / assignment / @mentions | Not implemented |
| Device sync | Durable outbox and checked server polling prepared; disabled until backend deployment. Live cross-device verification pending |
| Offline | Local persistence, cached web runtime and cloud queue; reconnect/cache eviction acceptance testing pending |
| Google / Outlook | Manual ICS export; no OAuth or two-way sync |
| Keyboard shortcuts | Ctrl/Cmd+N capture, K search, Z undo |
| Home widget | Android and iOS 17 Today widgets with durable tap-to-complete queues supplied; neither native platform is compiled/device-verified here |
| Notification / share capture | Android notification, Quick Settings tile, text share intent source; uncompiled and unverified |
| Custom categories / projects | Five defaults plus Other… in both pickers; creation and reload tested |

Files stay device-local: 1 MB per file, five files and 2 MB combined per task. Browser origin storage quotas also apply. Export JSON before clearing browser data.

RRULE supports DAILY/WEEKLY/MONTHLY/YEARLY, INTERVAL, BYDAY, BYMONTHDAY, BYMONTH, COUNT or UNTIL, WKST. Yearly ordinal weekdays require BYMONTH. ICS contains current time blocks, not recurring series.

After deployment, checked sync stores /users/{uid}/records and uses last-write-wins for simultaneous changes to one record. Attachments do not enter cloud records. Legacy cloud snapshots require explicit migration.

Preview mode is temporary sample data and skips Firebase initialization. Normal mode persists on this browser origin. Account sync is paused until the hardened backend is deployed. Older owner-only rules remain deployed. No public hosting, calendar connection or Play Store publication occurred.
