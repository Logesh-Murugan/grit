# Part C — iOS experience in GRIT 0.5

## Implemented

On compact layouts, GRIT uses CupertinoSliverNavigationBar with collapsing large titles and a CupertinoTabBar for Today, Upcoming, Inbox and Browse. The desktop sidebar remains available. Task capture and details use a draggable CupertinoSheetRoute. Project/category/view action pickers use Cupertino action sheets instead of web-style dropdowns on phones. Date/time selection in capture uses a CupertinoDatePicker.

Task rows support swipe right to complete, swipe left to reveal Schedule/Trash, and long-press quick actions. Trash is recoverable and completion has Undo. Select tasks to reveal list reorder handles. Board cards and calendar agenda retain their drag targets. Completion, priority changes and successful drag/drop use Flutter's native haptic channel; browser previews cannot demonstrate physical haptics.

Sheet transitions, completion checkmarks, swipe settling and reorder lift use spring simulations. Pull-to-refresh uses an unfolding leaf glyph with a pulse during refresh and a success state afterward. It refreshes checked sync when connected; a local workspace reports its local status. Custom motion respects the system Reduce Motion setting.

Appearance offers System, Light and Dark plus a Pure black OLED canvas. The system setting follows device brightness. iOS uses the platform SF text font without distributing Apple's font files; other platforms use Flutter's system fallback. Functional text inherits Flutter's platform text scaler, with no global text-size clamp. Task titles are 17 pt on phones. Task completion and interactive pill controls have 44-point hit regions. The brand wordmark and native tab labels retain fixed sizes, matching the distinction Apple makes between content and navigation typography. iOS does not expose a universal user-selected accent color through this app; GRIT keeps its coral accent.

Onboarding, local-storage microcopy and illustrated empty states are retained. Layout fixes let onboarding, Today, Settings, capture and expanded capture render at 3× text scaling on a 390×844 viewport. This is a tested subset, not a claim that every screen has passed VoiceOver or every accessibility size.

## Today widget: native source ready, device verification pending

The Xcode project includes an embedded GritTodayWidget extension (iOS 17+) and shared Swift source in both targets. SwiftUI uses system typography, light/dark rendering, small/medium/large families, and an AppIntent completion button. A widget tap removes the visible task and durably queues the completion in the App Group file. The Flutter app reconciles it on foreground/resume and while open, persists the workspace before acknowledging it, and prevents cross-account or stale-occurrence completion. The widget has a day-staleness prompt to reopen GRIT after midnight.

This is offline local widget functionality. It does not independently sync cloud data or schedule background reminders. Cloud propagation waits for the app and the separately deployed secure backend. Widgets aren't available in a browser preview.

Windows cannot compile, sign or run WidgetKit. Project OpenStep syntax, object references, target embedding/source membership and XML plists were checked here. **No iPhone or Xcode build has been performed.** Follow [IOS-SETUP.md](IOS-SETUP.md) before claiming this is a working installable iOS release.

## Verification

59 Flutter tests passed, including swipe completion/undo, swipe trash/undo, long-press actions, native capture route and drag dismissal, priority haptic dispatch, 2× and 3× text scaling, system/OLED persistence, Reduce Motion, durable account-scoped widget completion replay and stale scheduling. Analysis has no issues. Release web build and browser inspection are recorded in VERIFICATION.md.

## References and access limits

The Mobbin connector was explicitly attempted. It returned “Mobbin MCP requires a paid plan.” No paid plan was activated and no Mobbin reference screens were retrieved.

Implementation guidance was checked against Apple's [typography](https://developer.apple.com/design/human-interface-guidelines/typography), [sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [motion](https://developer.apple.com/design/human-interface-guidelines/motion), and [interactive widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), plus Flutter's [platform adaptations](https://docs.flutter.dev/ui/adaptive-responsive/platform-adaptations) and [accessibility guidance](https://docs.flutter.dev/ui/accessibility/ui-design-and-styling).

Auxiliary account/backup/filter forms still use Flutter Material dialogs. Full UIKit-only presentation, actual Dynamic Type/VoiceOver behavior, contrast review, device haptics, widget scheduling, and iPad ergonomics require native acceptance work. No award or App Store acceptance is promised. AI remains skipped; the Part B cloud deployment and Part A collaboration/calendar gaps remain open.

## October 3 UI/UX pass (0.9 preview)

Today and task completion were prioritized. The phone keeps its collapsing Cupertino large title and native tab bar. View selection is now a Cupertino sliding segmented control with 44-point item content; accessibility text sizes use an action-sheet choice instead of compressing four labels. The date subtitle is shorter so tasks are closer to the top.

Task completion now dispatches its haptic immediately and collapses the row using a spring before persisting completion. The existing spring checkbox, swipe-right completion, swipe-left schedule/trash, undo, long-press actions, custom pull refresh and reorder lift remain. Custom completion motion follows Reduce Motion, including a preference change while mounted.

Phone task details now occupy a draggable sheet surface, with dedicated close/edit chrome, independently scrolling content, grouped metadata/custom fields and reachable Complete/Focus controls. Larger text stacks those controls vertically. Priority and scheduled date are directly editable via native action sheets. Project views add a real completion summary and simplify Board cards to one surface each.

Typography continues to use the platform SF text font on Apple targets without distributing Apple's font files. Body content inherits the platform text scaler. Onboarding now has a shorter headline, clearer optional-name copy and a Cupertino capacity slider. Empty-state illustrations adapt to dark appearance. Small tag text is adjusted to meet a 4.5:1 contrast ratio on its actual pill background, preserving the tag hue. Dark appearance uses a brighter coral for link/control foregrounds; OLED retains a black canvas and elevated dark surfaces.

Validation: 66 Flutter tests passed, including immediate completion haptic dispatch, spring collapse plus Undo, 3x phone details in Light/Dark/OLED with completion controls on screen, and colored-caption contrast checks. Existing gestures, project drag/drop, capture, custom fields and widget replay tests pass. No iPhone hardware haptic test, VoiceOver audit, Xcode signing or WidgetKit device run has been performed. The iOS widget implementation and its remaining setup requirements are unchanged; see IOS-SETUP.md.

Guidance: Apple [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) and [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode). These changes aim to follow the guidance; they are not an award or certification claim.
