# GRIT v2 — Full Product Spec & Build Prompt
### A multi-user student productivity platform (academics + assignments + personal projects + daily habits, unified and auto-prioritized)

This is written to be handed to Codex/GPT in sections. It's longer than a single prompt on purpose — paste it section by section (Section 1 first, then 2, etc.) so the coding agent builds it in a sane order instead of trying to generate everything at once.

---

## 0. Product Vision

**GRIT** is a student productivity platform that solves one specific problem every student has: *things come from too many places* — professors assign coursework, classes have their own deadlines, you have personal projects (portfolio, hackathons, placement prep), and you're also trying to build daily habits (DSA, reading, exercise, communication). No single list captures all of it, so students either run four different apps or run nothing at all and forget things.

GRIT is **one inbox for everything a student has to do**, with an engine that automatically tells them what to do *right now* based on real urgency and importance — not just a flat checklist they have to manually sort every morning.

---

## 1. Target User & Core Problem

- A student (school, college, or university) juggling: coursework/assignments with hard deadlines, class-specific tasks, personal projects (portfolio, side projects, hackathons, exam/placement prep), and recurring daily habits.
- They currently either use nothing, or use 3-4 disconnected tools (a notes app for assignments, a habit tracker, a mental list for personal projects) and things fall through the cracks between them.
- The core unmet need: **"Just tell me what I should actually work on right now, out of everything I have going on."**

---

## 2. The Prioritization Engine (this is the core IP of the product — build this first and get it right)

Every single item in GRIT — an assignment, a class task, a personal project step, or a daily habit — is stored as one unified `Task` object (see data model in Section 5). Every task gets a computed **Priority Score**, recalculated live, that determines what shows up first in the student's daily agenda.

### 2.1 Inputs per task
- `deadline` (nullable — habits typically have none, assignments/exams always do)
- `importance` — 1 to 5, either set manually by the user or defaulted by category (Assignments/Exams default to 4-5, Personal Projects default to 3, Habits default to 2-3, adjustable any time)
- `estimated_effort_minutes`
- `category` (Assignment, Class Work, Personal Project, Habit, Exam/Event)
- `status` (not_started, in_progress, done, overdue)

### 2.2 Urgency calculation
Urgency should **not** scale linearly with time-until-deadline — it should stay low while a deadline is far away and spike sharply as it approaches, matching how humans actually feel pressure. Use an inverse/exponential curve, for example:

```
urgency = 1 / (1 + hours_until_deadline / K)
```

Where `K` is a tuning constant (e.g. 48) that controls how many hours out urgency starts noticeably rising. Tasks with no deadline (most habits) get a flat, low baseline urgency instead, so they don't disappear from the agenda entirely but also don't crowd out real deadlines.

### 2.3 Priority Score formula
```
priority_score = (importance × 0.6) + (urgency × 0.4) + effort_adjustment
```
- `effort_adjustment`: a small positive nudge for low-effort tasks when the student has limited time left in their day (surfaces "quick wins" — this directly helps on days with little time, a common student reality)
- Weights (0.6/0.4) should be a configurable constant, not hardcoded — you'll want to tune this after real usage data comes in

### 2.4 Daily Agenda logic (this is what actually appears on the home screen)
- The student sets (once, in onboarding) their realistic daily available study/work time (e.g. "I have about 4 hours a day outside class")
- Each morning (or on-demand), GRIT generates a **ranked, capacity-aware agenda**: take all open tasks, sort by `priority_score` descending, and fill the day's list until the cumulative `estimated_effort_minutes` hits the student's stated daily capacity — don't just dump every open task on them (this directly avoids the "wall of unchecked boxes" failure mode common to other trackers)
- Anything that doesn't fit today rolls forward automatically, with its urgency naturally increasing tomorrow as the deadline gets closer
- The student can always manually override — drag a task up, mark something "do today regardless," or snooze something a day

### 2.5 Eisenhower-style Matrix view (secondary view, same underlying data)
Offer a 2×2 view (Urgent/Important) derived from the same `urgency`/`importance` values — useful for a weekly planning session even though the daily agenda is what drives day-to-day use.

### 2.6 Overdue & Smart Reschedule
- Fixed-deadline tasks (assignments, exams) that pass their deadline incomplete get flagged `overdue` and stay visibly pinned at the top until resolved — never silently disappear
- Flexible tasks (habits, personal project steps) that don't get done today auto-roll into tomorrow rather than being marked "failed," since punishing every miss is what causes people to quit (see Section 8)

---

## 3. Feature Set

### 3.1 Unified Task Inbox
- Quick-add from anywhere (one tap/shortcut), with smart category detection where possible (e.g. typing "DSA" suggests Habit category, typing "submit" suggests Assignment)
- Bulk import for coursework: paste/photograph a syllabus or assignment list and let an LLM call parse it into structured tasks with deadlines (high-value feature — this is the kind of thing that makes students actually adopt a new tool, since manual entry is the #1 onboarding killer)

### 3.2 Streaks, Heatmap, XP (carried over from the original spec)
- Per-category streaks for habits specifically (not assignments — a missed assignment isn't a "streak break," it's just overdue)
- GitHub-style contribution heatmap
- XP and levels for completed tasks, scaled to effort
- **Streak Freeze** — one protected miss per week so a single bad day doesn't erase weeks of consistency

### 3.3 Events (generalized from "Hackathons")
A distinct entity for anything with its own timeline and sub-checklist: exams, hackathons, project submissions, interviews. Each has: title, key dates (registration/prep/submission/event), a prep checklist of its own sub-tasks (which feed into the same priority engine), and a countdown card on the dashboard when upcoming.

### 3.4 AI Assistant / Coach
- Proactive nudges if no activity by a set time
- Evening "Live Recap" summarizing the last few days in plain language
- Pattern detection ("this keeps slipping 4 out of 5 days") with a suggested fix, not just a guilt trip
- Natural-language check-in ("done with the DBMS assignment") that finds and completes the matching task
- Ground every response in the student's real current task/streak data via an LLM call — never generic motivational text

### 3.5 Multi-Channel Reminders
- Push notifications (native, since this is now a real mobile app — see Section 6)
- Telegram bot and/or email as lower-friction companions to push
- Every reminder actionable in one tap/reply — complete or snooze without opening the app

### 3.6 Analytics
- Weekly/monthly completion trends per category
- "Consistency score" combining streak health + completion rate
- Syllabus/course-level progress view for academic tasks specifically (e.g. "Data Structures: 60% of planned tasks complete, exam in 12 days")

### 3.7 Premium UI/UX
- Dark theme by default, one consistent accent color, glassmorphism cards, smooth micro-interactions, designed empty/loading states, consistent icon system — should feel like a paid product, not a college project (full detail retained from the earlier UI spec if you have it; ask me to resend if needed)

---

## 4. Multi-Tenant Architecture Requirements

This is a real product with real users now, which changes the engineering requirements significantly from a personal tool:

- **Per-user data isolation** — every task, streak, and setting is scoped to a `user_id`; no user can ever read another user's data (enforce this at the database rules/security layer, not just in app logic)
- **Authentication** — email/password plus Google Sign-In (students overwhelmingly prefer one-tap Google login; friction here directly kills signup conversion)
- **Cloud-synced, offline-capable** — a student's data must be available across their phone and any other device, and the app should remain usable (queue changes) with no signal, syncing once back online
- **Scalable from day one but cheap at low usage** — use a backend that scales to zero cost at zero users and scales up smoothly (see stack recommendation below), since you don't want fixed server costs before you have paying users

---

## 5. Data Model (core collections/tables)

```
users
  id, email, name, onboarding_complete, daily_capacity_minutes,
  reminder_channels[], premium_status, created_at

tasks
  id, user_id, title, notes, category (assignment|class_work|personal_project|habit|event),
  importance (1-5), deadline (nullable), estimated_effort_minutes,
  status (not_started|in_progress|done|overdue), completed_at,
  recurrence_rule (nullable, for daily habits), parent_event_id (nullable, links to events)

events
  id, user_id, title, type (exam|hackathon|interview|submission),
  key_dates{registration, prep_start, submission, event_date},
  status

streaks
  id, user_id, category_or_task_id, current_streak, longest_streak,
  freezes_available, last_completed_date

subscriptions
  id, user_id, plan (free|premium), status, renewal_date, payment_provider_ref
```

---

## 6. Recommended Tech Stack (for a real Play Store app, built via Codex/GPT)

Since the goal is Play Store publication (not just a web app), the stack needs to produce an actual installable Android app:

- **Frontend: Flutter.** Single codebase, compiles to a real native Android app (and iOS later for free), huge library ecosystem, and is very well-represented in GPT/Codex's training data — meaning code generation quality for Flutter is reliably strong, which matters a lot when you're building solo with an AI coding agent.
- **Backend: Firebase** (Firestore for the database, Firebase Auth, Cloud Functions for the priority-scoring and AI assistant logic, Firebase Cloud Messaging for push notifications). This combination is specifically chosen because: it scales to zero cost with no users, has built-in per-user security rules (solving the multi-tenant isolation requirement directly), and is the single most common stack for solo/small-team student and productivity apps — meaning Codex will have strong patterns to draw from.
- **AI Assistant logic**: Cloud Functions calling the Claude or GPT API, fed the student's current task/streak state as context per request.
- **Payments** (for the premium tier): Google Play Billing library, since in-app subscriptions on Android must go through Play Billing to comply with Play Store policy — don't build custom payment logic for this.

---

## 7. Monetization

- **Free tier**: unlimited manual task tracking, streaks, heatmap, basic push reminders — the core loop must be genuinely useful for free, or you'll never get the retention/reviews needed to rank
- **Premium (subscription, e.g. $2-4/month or a local-currency equivalent)**: AI Assistant, syllabus auto-import, Telegram/WhatsApp reminders, advanced analytics, premium themes
- Keep the paywall honest — never gate basic task tracking, since a tracker that's crippled for free will get uninstalled before it ever earns a review

---

## 8. Why This Needs to Beat Existing Trackers (carried forward, now applied to the general-student scope)

Real, documented reasons people abandon Notion/Habitica/Streaks-style trackers, and how GRIT should specifically avoid each:
1. **Passive tools require the user to remember to open them** → GRIT pushes to the student proactively (reminders + assistant), it doesn't wait
2. **Setup becomes the procrastination** → zero-setup categories, syllabus auto-import, sensible defaults
3. **Too many items visible at once causes shutdown** → capacity-aware Daily Agenda, never a raw dump of everything open
4. **A checkbox has no real accountability** → the AI Assistant plays that role with proactive check-ins
5. **All-or-nothing streaks punish one bad day** → Streak Freeze, and habits vs. deadlines are never treated the same way
6. **No memory of the journey** → heatmap + Live Recap turn history into something that's actually visible and spoken back to the student

---

## 9. Launch Checklist (beyond the code — this determines whether you actually reach #1, not just whether the app works)

- **Privacy Policy & Terms of Service** — legally required for Play Store submission the moment you store real user data (email, tasks, usage). Since you're in India, be aware of the DPDP Act's requirements around user consent and data handling in addition to Play Store's own policy — a simple, honest, clearly-written policy is enough at this stage, but it cannot be skipped.
- **Store listing**: Google's ranking weighs metadata optimization, user engagement and retention, technical performance (Android Vitals), ratings and reviews, install volume, update frequency, and localization — write your title/description around how students actually search ("student planner," "assignment tracker," "study habit tracker"), not just your brand name.
- **Closed beta first**: launch to a small group (your own college/department) before a public push — this is how you get your first genuine reviews and catch crashes before they hurt your Day-1/Day-7 retention numbers, which Google now weighs as one of the strongest ranking signals, with healthy benchmarks around 35% Day-1 and 15% Day-7 retention.
- **Review velocity matters** — actively (and honestly) ask satisfied users to leave a review right after a genuine win (e.g. hitting a 7-day streak), since review velocity often outweighs the raw average rating in ranking.
- **Ship updates regularly** post-launch — update cadence is itself a ranking factor, and it also gives you a reason to re-engage lapsed users.

---

## 10. Build Order for Codex

1. Data model + Firebase Auth + basic CRUD for tasks (get the unified inbox working end to end, no scoring yet)
2. Prioritization engine (Section 2) + capacity-aware Daily Agenda — this is the core differentiator, get it right before adding anything else
3. Streaks, heatmap, XP
4. Events (exams/hackathons/submissions)
5. Push notifications + Telegram companion channel
6. AI Assistant (Cloud Function + LLM integration)
7. Premium UI/UX pass
8. Play Billing integration for the premium tier
9. Closed beta → Play Store submission