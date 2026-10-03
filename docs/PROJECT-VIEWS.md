# Project views and quick capture

Projects offer List, Board, Calendar and Schedule. The selected view is saved per project.

## Board
Long-press a card and drop it into another section. An Unsectioned column is always available, including for projects with no sections. The move updates the same task and its subtasks' section/project association. Dropping onto the Calendar view switch opens Calendar without changing task data; the task can then be dropped onto a date.

## Calendar
Unscheduled tasks are available above the month grid. Long-press to drop onto a date. Dated tasks appear in the selected-day agenda and can be dragged to another date. Rescheduling preserves their hour and minute. Drop into Unscheduled to remove the scheduled date. Deadline, priority, labels and board section remain independent. A calendar drop opens the destination day's agenda. Dropping onto Board switches back to the same project tasks.

## Quick add
`Submit report tomorrow 5pm p1 #Work @urgent` saves:
- Title: Submit report
- Scheduled date: tomorrow, local time 17:00
- Priority: P1
- Project: existing project Work (case-insensitive matching)
- Label: urgent

Use `#"Client work"` for project names containing spaces. An unknown project produces an actionable validation message; it does not silently create a project or lose the entered task. Explicit P4 overrides the editor's previous priority. Dates affect the scheduled date, not the separate deadline. Parsing can be disabled in task capture.

## Verification
63 Flutter tests passed, including actual long-press drag gestures between board columns, Board-to-Calendar view switch, unscheduled-to-date, date-to-date preserving time, and date-to-unscheduled. Tests also verify project-view persistence and quick capture metadata after save/reload. Static analysis and web release build checked separately. Native touch behavior still requires device acceptance testing.
