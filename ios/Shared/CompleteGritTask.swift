import Foundation
import WidgetKit
import AppIntents

@available(iOS 17.0, *)
struct CompleteGritTask: AppIntent {
    static var title: LocalizedStringResource = "Complete task"
    static var description = IntentDescription("Complete a task in your GRIT Today widget.")
    @Parameter(title: "Task") var taskId: String
    @Parameter(title: "Workspace") var workspace: String
    @Parameter(title: "Scheduled occurrence") var scheduled: String?
    init() {}
    init(taskId: String, workspace: String, scheduled: String?) {
        self.taskId = taskId; self.workspace = workspace; self.scheduled = scheduled
    }
    func perform() async throws -> some IntentResult {
        guard GritWidgetStore.complete(taskId, workspace: workspace, scheduled: scheduled) else { throw CocoaError(.fileWriteUnknown) }
        WidgetCenter.shared.reloadTimelines(ofKind: "GritToday")
        return .result()
    }
}
