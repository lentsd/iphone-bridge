import AppKit
import Foundation

// Ask only our generated app at the exact path to quit. Its delegate can refuse
// while a file transfer is in progress. Never force-terminate a device operation.
let expected = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
func matchingApps() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: "local.personal.iphonebridge").filter {
        $0.bundleURL?.standardizedFileURL == expected && !$0.isTerminated
    }
}
let apps = matchingApps()
for app in apps { _ = app.terminate() }
let deadline = Date().addingTimeInterval(5)
while !matchingApps().isEmpty && deadline.timeIntervalSinceNow > 0 {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
if !matchingApps().isEmpty {
    fputs("App is still busy; update has not replaced the running app.\n", stderr)
    exit(2)
}
print("Ready to update. Closed app instances: \(apps.count).")
