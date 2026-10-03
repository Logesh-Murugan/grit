# Part B: implemented in 0.4

## Local features

- Board cards have category-colored outlines, estimate chips, custom-field previews and actual-time summaries. Project navigation has completion rings.
- Settings has Compact, Comfortable and Spacious task densities; saved across restarts and included in backups.
- Task details has Add custom field, edit and remove. Types: Text, Number, Checkbox, Date. Names are user-defined, duplicate names are rejected, dates and values are validated. Fields are included in local persistence, backups and cloud record payloads.
- Per-task focus sessions persist their start, accumulated active milliseconds and session identifier. Paused time is excluded. Closing or finishing saves a timestamped duration once; completing a task also finishes the timer. Duplicating a task retains its field definitions but starts with no time history. Unattended timers cap at the chosen session length (up to 25 minutes).
- Gamification defaults off. The opt-in toggle controls XP/levels, goal streaks, goal banners and completion praise. Basic completion charts and habit history remain useful without XP.
- AI was explicitly skipped. No AI endpoint, API key requirement or paid AI call is included in the new Functions entrypoint.

## Session security: source implemented; production deployment pending

The older deployed owner-only Firestore rules do not check token revocation. They remain the live project's rules until the new deployment is made. **Do not claim production session invalidation is complete.**

The 0.4 client removes direct Firestore sync. All new server data access is through readRecords/writeRecords callable Functions, which call Firebase Admin verifyIdToken(token, true) on every operation. UID is taken from that verified token, never a client path. The separate hardened rules deny every client Firestore read/write, closing the direct-access bypass. Admin Functions retain server access.

Firebase invalidates refresh tokens after major account changes such as password changes. MFA enrollment also revokes existing refresh tokens. The Admin revocation check rejects surviving old ID tokens instead of accepting them until their one-hour expiry. Sign out on every device writes a server-only cutoff and calls revokeRefreshTokens, requiring recent sign-in. The cutoff rejects same-second sessions as well; a new sign-in in the next second succeeds. No MFA enrollment UI has been implemented in this pass.

References: [Firebase session management](https://firebase.google.com/docs/auth/admin/manage-sessions), [MultiFactorUser enrollment](https://firebase.google.com/docs/reference/js/auth.multifactoruser#multifactoruserenroll).

SECURE_SYNC_ENABLED defaults false until deployment is verified. Authentication and account-local persistence remain available; the outbox retains account edits. No insecure direct-access fallback is enabled. Once connected, this implementation polls the checked server every 10 seconds; it is not a live shared-project collaboration service. Attachments remain local.

## What the owner must finish

1. Set up Firebase billing yourself for grit-4da5a (Cloud Functions requires Blaze). No billing change has been made by Codex.
2. Install backend/functions dependencies and deploy the Functions plus hardened rules together, using firebase.secure.json. Do not deploy only the Functions while leaving direct-access rules permissive.
3. Test real account password change/reset, MFA enrollment and sign out on every device in two sessions. Each old session must be rejected on read and write; a fresh sign-in must succeed. Current tests mock Admin revocation and test Firestore rules in an emulator; they are not live Auth/MFA verification.
4. Build with --dart-define=SECURE_SYNC_ENABLED=true only after those checks. Keep firebase.local.json private from source archives; its public Firebase config is already ignored locally.

Owner deployment commands (not executed):

```powershell
cd 'C:\Users\Logesh\Documents\Codex\2026-09-30\this\outputs\grit\backend\functions'
npm install
npm test
cd '..\..'
firebase deploy --project grit-4da5a --config firebase.secure.json --only functions,firestore:rules
flutter build web --release --dart-define-from-file=firebase.local.json --dart-define=SECURE_SYNC_ENABLED=true
```

## Verified in this pass

50 Flutter tests passed, including invalid backup rejection, typed-field persistence, density settings, long-field mobile Board layout, pause/resume accounting, timer recovery, duplicate-task history reset and focus-dialog close behavior. Static analysis: no issues. Release web build succeeded. Eight server policy tests passed; ten hardened rules checks passed in the Firestore emulator. Live Functions deployment and Android build/device checks are not completed.

Earlier Part A gaps (shared projects, OAuth calendar sync, Android release validation and Play Store publishing) are still open; see RELEASE-GAPS.md.

## October 3 audit (0.8 preview)

The task features remain available: Text/Number/Checkbox/Date custom fields, actual vs estimated focus time, opt-in XP and three card densities. This audit adds category-tinted card surfaces/borders, project-card completion rings and current-session elapsed minutes in the timer. The 63 Flutter tests pass and analysis is clean.

Server policy changes:
- Every read/write re-verifies the token with Admin's revocation flag and fetches the current Auth user record.
- The token's original auth_time must be strictly later than tokensValidAfterTime. Refreshing the old session's ID token cannot satisfy this requirement. Same-second pre-change sessions are conservatively rejected; sign in after the cutoff second. A just-created account may also need a fresh sign-in after that second.
- Disabled accounts, missing/invalid account cutoffs, failed account lookup, invalid identity and malformed private policies fail closed.
- Concurrent sign-out-all operations use a transaction with a monotonic cutoff so an earlier request cannot overwrite a later revocation time.
- The client remains unable to use direct Firestore as a fallback. The default deployment config and firebase.secure.json both use deny-all client rules.

11 server policy tests pass, including the timestamp boundary and refreshed account policy. These tests use mocked Admin Auth; they do not prove live password reset/MFA behavior. Firebase's official [session management](https://firebase.google.com/docs/auth/admin/manage-sessions) and [MFA enrollment](https://firebase.google.com/docs/reference/js/auth.multifactoruser#multifactoruserenroll) document the account-change revocation behavior used here.

**Production release gate:** enable billing, deploy Functions and hardened rules together, then test password change/reset, successful second-factor enrollment and sign-out-all with two real sessions. The old bearer must fail both readRecords and writeRecords; refreshing the old session must not regain access; a fresh sign-in after the cutoff must succeed. Repeat via direct Firestore requests to confirm they are denied. Do not enable SECURE_SYNC_ENABLED until those checks pass. No live security deployment, billing change, password change or MFA enrollment was performed in this audit. No MFA enrollment screen is implemented yet.
The hardened Firestore rules also passed 10 emulator checks in this audit: owner, other-user and anonymous direct reads/writes/listing are denied; trusted server writes succeed. This is local emulator evidence, not a production deployment.
Browser acceptance: creating a Course field on a sample task displays its saved value in task details. The focus dialog exposes Start/Pause and shows current-session elapsed time alongside logged time and estimate. Screenshots are included in the preview package. Preview edits are sample-only.
