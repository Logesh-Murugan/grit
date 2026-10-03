import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var gritChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "grit/platform", binaryMessenger: controller.binaryMessenger)
      gritChannel = channel
      channel.setMethodCallHandler { call, result in
        do {
          switch call.method {
          case "updateWidget":
            guard let args = call.arguments as? [String: Any] else {
              result(FlutterError(code: "arguments", message: "Widget snapshot missing", details: nil)); return
            }
            let data = try JSONSerialization.data(withJSONObject: args)
            let snapshot = try JSONDecoder().decode(GritWidgetSnapshot.self, from: data)
            let success = GritWidgetStore.change { state in
              let pending = Set(state.completions.filter { $0.workspace == snapshot.workspace }.map(\.taskId))
              state.snapshot = GritWidgetSnapshot(workspace: snapshot.workspace, day: snapshot.day,
                tasks: snapshot.tasks.filter { !pending.contains($0.id) })
            }
            guard success else { throw CocoaError(.fileWriteUnknown) }
            WidgetCenter.shared.reloadTimelines(ofKind: "GritToday")
            result(nil)
          case "widgetCompletions":
            let data = try JSONEncoder().encode(GritWidgetStore.read().completions)
            result(try JSONSerialization.jsonObject(with: data))
          case "ackWidgetCompletions":
            let ids = Set(call.arguments as? [String] ?? [])
            guard GritWidgetStore.change({ $0.completions.removeAll { ids.contains($0.id) } }) else {
              throw CocoaError(.fileWriteUnknown)
            }
            result(nil)
          case "takeQuickAdd": result(nil)
          default: result(FlutterMethodNotImplemented)
          }
        } catch {
          result(FlutterError(code: "widget_storage", message: error.localizedDescription, details: nil))
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(_ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if url.scheme == "grit", url.host == "today" {
      gritChannel?.invokeMethod("showToday", arguments: nil)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
