# Owner service setup

0.4 update: AI is skipped. Authentication can use the configured project, but sync stays local until the revocation-checking Functions and hardened rules are deployed and SECURE_SYNC_ENABLED is enabled. Follow [PART-B.md](PART-B.md); older personal-sync/coach instructions below are superseded.

Your Firebase project grit-4da5a, GRIT Web app, Email/Password and Google sign-in providers, and default Firestore database in Mumbai now exist. Owner-only rules are published. The ignored firebase.local.json is configured locally. Build with its defines to activate personal sync. No password or verification code should be sent to this chat.

Create a GRIT project in your account, select its permanent Firestore region, register a web app, and enable Email/Password Authentication. Review service terms yourself. Copy firebase.example.json to firebase.local.json and fill in public client configuration, then set FIREBASE_ENABLED to true.

From the folder containing pubspec.yaml, run:

```powershell
flutter run -d chrome --dart-define-from-file=firebase.local.json
```

Review backend/firestore.rules. The included emulator suite passed 15 owner-isolation checks. The personal path is /users/{uid}/records/{recordId}. These rules do not implement shared projects. Never place service-account keys or OAuth client secrets in Flutter code.

Existing local data and legacy /planner/state documents need a reviewed migration before using the record adapter with real data. No live data migration has occurred. Export a local JSON backup before signing in, then restore it into your signed-in workspace if desired; each account has a separate local cache.

Install Android Studio and its SDK from the official Android developer website; complete SDK license acceptance yourself. Run flutter doctor, then flutter build apk --release in this project folder. Verify widgets, notification permission, Quick Settings capture and share intent on real devices before release.

Settings exports time blocks to an ICS file for manual calendar import. Google/Outlook OAuth, token handling and two-way synchronization still need implementation; creating credentials alone will not activate them.
