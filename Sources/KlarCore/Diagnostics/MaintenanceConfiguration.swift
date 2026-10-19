import Foundation

public enum MaintenanceConfiguration {
    public static func validFeed(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        return url
    }

    public static func validPublicKey(_ value: String?) -> Bool {
        guard let value, let data = Data(base64Encoded: value) else { return false }
        return data.count == 32
    }

}
