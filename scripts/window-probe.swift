import CoreGraphics
import Foundation

let arguments = CommandLine.arguments

guard arguments.count == 3, let pid = Int32(arguments[1]) else {
    fputs("usage: window-probe PID EXPECTED_TITLE\n", stderr)
    exit(2)
}

let expectedTitle = arguments[2]
let windows = (CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]]) ?? []

let owned = windows.compactMap { window -> (Int, String, [String: Any])? in
    let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
    guard ownerPID == pid else { return nil }
    let number = (window[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
    let title = window[kCGWindowName as String] as? String ?? ""
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    return (number, title, bounds)
}

for (number, title, bounds) in owned {
    print("WINDOW id=\(number) title=\(title) bounds=\(bounds)")
}

let matches = owned.filter { $0.1 == expectedTitle && $0.0 > 0 }
print("WINDOW_COUNT=\(owned.count) EXPECTED_MATCHES=\(matches.count)")

guard let match = matches.first else { exit(1) }
print("MATCHED_WINDOW_ID=\(match.0)")
