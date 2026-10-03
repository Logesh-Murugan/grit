import 'domain.dart';
import 'planning.dart';
import 'store.dart';

void loadShowcase(GritStore s) {
  final n = DateTime.now(), today = day(DateTime.now());
  s.projects = [
    Project(
        id: 'uni',
        name: 'University',
        color: 0xFF748DB1,
        icon: 'school',
        favorite: true,
        description: 'A little progress between classes.',
        sections: ['Assignments', 'Study sessions', 'Reading']),
    Project(
        id: 'life',
        name: 'Personal',
        color: 0xFF96A080,
        icon: 'spa',
        favorite: true,
        sections: ['This week', 'Someday']),
    Project(
        id: 'launch',
        name: 'Portfolio website',
        color: 0xFFBA91B8,
        icon: 'code',
        favorite: true,
        sections: ['Ideas', 'In progress', 'Ready to ship']),
    Project(
        id: 'habits',
        name: 'Daily rituals',
        color: 0xFFE8B35E,
        icon: 'sun',
        sections: ['Morning', 'Evening'])
  ];
  s.tasks = [
    Task(
        id: 'brief',
        title: 'Finish the research proposal',
        notes:
            'Bring together the problem statement, literature review, and research questions. Aim for a clear first draft, not a perfect one.',
        projectId: 'uni',
        section: 'Assignments',
        category: Category.assignment,
        importance: 5,
        priority: 1,
        minutes: 60,
        scheduled: today.subtract(const Duration(days: 1)),
        deadline: DateTime(n.year, n.month, n.day, 23, 59),
        labels: [
          'deep-work'
        ],
        comments: [
          {
            'text': 'Keep the introduction focused on one research question.',
            'author': 'Me',
            'at': n.subtract(const Duration(hours: 2)).toIso8601String()
          }
        ]),
    Task(
        id: 'read',
        title: 'Read 10 pages with your morning coffee',
        projectId: 'habits',
        section: 'Morning',
        category: Category.habit,
        minutes: 15,
        scheduled: today,
        recurrence: 'daily',
        labels: ['personal'],
        history: List.generate(
            5, (i) => dayKey(today.subtract(Duration(days: i + 1))))),
    Task(
        id: 'design',
        title: 'Design the portfolio case study',
        notes: 'Tell the story: the problem, the decisions, and the impact.',
        projectId: 'launch',
        section: 'In progress',
        category: Category.personalProject,
        priority: 2,
        importance: 4,
        minutes: 45,
        scheduled: DateTime(n.year, n.month, n.day, 10),
        labels: ['creative', 'deep-work']),
    Task(
        id: 'design-sub1',
        title: 'Collect the before & after screens',
        parentId: 'design',
        projectId: 'launch',
        section: 'In progress',
        minutes: 15,
        doneAt: n),
    Task(
        id: 'design-sub2',
        title: 'Write the story behind the design',
        parentId: 'design',
        projectId: 'launch',
        section: 'In progress',
        minutes: 20),
    Task(
        id: 'design-sub3',
        title: 'Add the final mockups',
        parentId: 'design',
        projectId: 'launch',
        section: 'In progress',
        minutes: 10),
    Task(
        id: 'lecture',
        title: 'Review notes from today’s lecture',
        projectId: 'uni',
        section: 'Study sessions',
        category: Category.classWork,
        minutes: 30,
        scheduled: DateTime(n.year, n.month, n.day, 14),
        labels: ['study'],
        priority: 3),
    Task(
        id: 'walk',
        title: 'Get outside for a 20-minute walk',
        projectId: 'life',
        section: 'This week',
        category: Category.habit,
        minutes: 20,
        scheduled: DateTime(n.year, n.month, n.day, 17, 30),
        recurrence: 'daily'),
    Task(
        id: 'plan',
        title: 'Plan a few good things for next week',
        projectId: 'life',
        section: 'This week',
        category: Category.personalProject,
        minutes: 15,
        scheduled: today.add(const Duration(days: 2))),
    Task(
        id: 'exam',
        title: 'Practice database exam questions',
        projectId: 'uni',
        section: 'Study sessions',
        minutes: 60,
        priority: 1,
        scheduled: today.add(const Duration(days: 1)),
        deadline: today.add(const Duration(days: 5)),
        eventId: 'exam-event'),
    Task(
        id: 'website',
        title: 'Publish the new homepage',
        projectId: 'launch',
        section: 'Ready to ship',
        minutes: 30,
        priority: 2,
        scheduled: today.add(const Duration(days: 3))),
    Task(
        id: 'idea',
        title: 'Find a good book for October',
        category: Category.personalProject,
        minutes: 10),
    Task(
        id: 'done1',
        title: 'Make a little room for the week',
        projectId: 'life',
        minutes: 10,
        doneAt: n),
  ];
  s.events = [
    GritEvent('exam-event', 'Database systems exam', 'Exam',
        today.add(const Duration(days: 5)))
  ];
  s.filters = [
    SavedFilter('important', 'High priority', 'p1 | p2'),
    SavedFilter('deep', 'Deep work', '@deep-work & !completed'),
    SavedFilter('week', 'This week', '7 days')
  ];
  s.activity = [
    {
      'verb': 'Completed',
      'title': 'Make a little room for the week',
      'at': n.toIso8601String()
    }
  ];
  s.onboarded = true;
  s.save();
}
