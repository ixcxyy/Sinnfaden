import Foundation

// All optional values are build-time public configuration, never access tokens.
let environment = ProcessInfo.processInfo.environment
let arguments = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
guard arguments.count == 3 else { fail("Usage: configure-release.swift source.plist output.plist") }
let source = URL(fileURLWithPath: arguments[1]), destination = URL(fileURLWithPath: arguments[2])
guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: source), format: nil) as? [String: Any] else { fail("Invalid source plist") }
for (variable, key) in [("KLAR_VERSION", "CFBundleShortVersionString"), ("KLAR_BUILD_NUMBER", "CFBundleVersion")] {
    if let value = environment[variable] {
        guard value.range(of: "^[0-9]+(\\.[0-9]+){0,2}$", options: .regularExpression) != nil else { fail("Invalid numeric release version") }
        plist[key] = value
    }
}
let feed = environment["KLAR_UPDATE_FEED_URL"] ?? plist["SUFeedURL"] as? String
let publicKey = environment["KLAR_UPDATE_PUBLIC_KEY"] ?? plist["SUPublicEDKey"] as? String
if feed != nil && publicKey == nil { fail("Provide a public signing key for the update feed") }
for (variable, key) in [("KLAR_UPDATE_FEED_URL", "SUFeedURL"), ("KLAR_BUG_REPORT_URL", "SinnfadenBugReportURL")] {
    if let value = environment[variable] {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { fail("Release endpoints must be HTTPS URLs without credentials or fragments") }
        plist[key] = value
    }
}
if let publicKey {
    guard Data(base64Encoded: publicKey)?.count == 32 else { fail("Invalid Ed25519 public key") }
    plist["SUPublicEDKey"] = publicKey
}
try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: destination, options: .atomic)
