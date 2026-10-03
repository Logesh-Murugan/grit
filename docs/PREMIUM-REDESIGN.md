# GRIT visual refresh — October 3, 2026

This pass changes Today and shared task cards. It is not a claim of complete Todoist parity or App Store readiness.

## Research
Lazyweb MCP search `daily planner task list` (mobile, five results) returned references including Structured, Tiimo, Superlist and Reminders. The returned screen descriptions informed clear daily hierarchy, visible completion state and quick focus/planning actions. Reference images were not copied into GRIT. Public product context: https://structured.app/visual-planning and https://culturedcode.com/things/index.html . Lazyweb: https://www.lazyweb.com/agent-access .

## Implemented
- Dark ink Today overview, live remaining task count, estimated effort and completion ring.
- Start focus opens the existing timer on the first unfinished task in the current ordering. Plan my day opens Schedule. No fake activity or sample-only controls.
- Empty overview hides Start focus when there is no unfinished task.
- White/surface task cards with stronger title weight, rounded borders and spacing; Board cards retain category accents.
- Your spaces project cards with actual progress and navigation. First four active projects appear here; all projects remain available in navigation.
- Layouts retain Dynamic Type, OLED/system themes, swipe actions, native sheets and existing custom category/project creation.

## Verification
Flutter static analysis passed. The original 59 tests passed after scrolling interaction tests to visible task targets. An additional overview test checks actions, empty state and 3x text sizing. See work/test-v06.log in the parent workspace for the final suite result. Web release build and local preview were refreshed.

## Remaining product work
This visual refresh does not deploy billing, secure server session checks, collaboration or calendar OAuth. Native iOS haptics/widgets still require a Mac/device validation pass. AI remains skipped at the user's request. Other screens retain the prior design and need further product-wide refinement before a paid launch.
