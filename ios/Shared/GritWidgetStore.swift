import Foundation

struct GritWidgetTask: Codable, Identifiable {
    let id: String
    let title: String
    let priority: Int
    let scheduled: String?
}
struct GritWidgetSnapshot: Codable {
    var workspace: String
    var day: String
    var tasks: [GritWidgetTask]
}
struct GritWidgetCompletion: Codable, Identifiable {
    let id: String
    let taskId: String
    let workspace: String
    let scheduled: String?
    let at: String
}
struct GritWidgetState: Codable {
    var snapshot: GritWidgetSnapshot?
    var completions: [GritWidgetCompletion] = []
}

// Both targets use this same file. File coordination prevents completion and
// app snapshot updates from overwriting each other across processes.
enum GritWidgetStore {
    static var group: String {
        Bundle.main.object(forInfoDictionaryKey: "GritAppGroup") as? String ?? "group.app.grit.grit"
    }
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("grit-today.json")
    }
    static func read() -> GritWidgetState {
        guard let url = url else { return GritWidgetState() }
        var state = GritWidgetState()
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { file in
            if let data = try? Data(contentsOf: file), let decoded = try? JSONDecoder().decode(GritWidgetState.self, from: data) { state = decoded }
        }
        return state
    }
    @discardableResult
    static func change(_ update: (inout GritWidgetState) -> Void) -> Bool {
        guard let url = url else { return false }
        var error: NSError?
        var success = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { file in
            var state = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(GritWidgetState.self, from: $0) } ?? GritWidgetState()
            update(&state)
            do {
                try JSONEncoder().encode(state).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
                success = true
            } catch { success = false }
        }
        return success && error == nil
    }
    static func todayKey(_ date: Date = Date()) -> String {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }
    static func complete(_ taskId: String, workspace: String, scheduled: String?) -> Bool {
        change { state in
            guard var snapshot = state.snapshot, snapshot.workspace == workspace,
                let task = snapshot.tasks.first(where: { $0.id == taskId && $0.scheduled == scheduled }) else { return }
            let day = DateFormatter()
            day.calendar = Calendar(identifier: .gregorian)
            day.locale = Locale(identifier: "en_US_POSIX")
            day.dateFormat = "yyyy-MM-dd"
            guard snapshot.day == day.string(from: Date()) else { return }
            let at = ISO8601DateFormatter().string(from: Date())
            state.completions.append(GritWidgetCompletion(id: UUID().uuidString, taskId: taskId,
                workspace: snapshot.workspace, scheduled: task.scheduled, at: at))
            snapshot.tasks.removeAll { $0.id == taskId }
            state.snapshot = snapshot
        }
    }
}
