# Production release work — GRIT 0.5

Deploy the new checked Functions and hardened rules after owner billing setup, then verify real password/MFA revocation before enabling SECURE_SYNC_ENABLED. See [PART-B.md](PART-B.md). AI is explicitly skipped. Earlier gaps below remain open.

The full requested checklist is not finished.

1. Owner Firebase services are configured and rules passed 15 emulator checks. Verify actual Dart adapter replay, cross-device edits and conflicts on two devices. Migrate legacy cloud snapshots explicitly.
2. Implement shared membership, invitations, roles, assignments, @mentions and collaborative comments, with tested authorization rules.
3. Implement Google/Outlook OAuth and incremental two-way calendar sync. ICS export is manual interoperability only.
4. Add cloud object storage and access rules. Current attachments remain local and in JSON backups.
5. Compile Android and test widgets, Quick Settings capture, notifications, share intent, lifecycle, accessibility and offline replay on real devices. Android SDK is absent here. Compile/sign the supplied iOS app and widget on macOS; configure App Groups and validate on an iPhone. See IOS-SETUP.md.
6. Implement background task reminders. Current reminders show banners while open; Android quick-add notification is a capture shortcut.
7. Test cache eviction, storage quota recovery, timezones/DST and upgrade recovery. Expand recurrence grammar with acceptance tests.
8. Complete account deletion, retention/privacy/support details, signing, Play Console testing and store assets.

AI, voice, syllabus extraction and billing remain inactive. Owner-only database rules were deployed; public hosting, APK/AAB and store submission were not. Adoption cannot be guaranteed by code.
