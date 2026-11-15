import Foundation
import HopHardwareKit
import Security

enum HardwareBundleValidation {
    static func validate(_ app: URL, identifier: String, team: String) throws {
        let helper = app.appendingPathComponent("Contents/Helpers/HopHardwareHelper.app")
        for (url, expected) in [(app, identifier), (helper, identifier + HardwareIdentity.helperSuffix)] {
            guard let text = HardwareIdentity.requirement(identifier: expected, team: team),
                  Bundle(url: url)?.bundleIdentifier == expected else { throw HardwareReason.unauthorized }
            var requirement: SecRequirement?, code: SecStaticCode?
            guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
                  SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code, let requirement,
                  SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), requirement) == errSecSuccess
            else { throw HardwareReason.unauthorized }
        }
        let file = app.appendingPathComponent("Contents/Library/LaunchDaemons/\(identifier).hardware.plist")
        let data = try Data(contentsOf: file)
        guard data.count <= 16384,
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              plist["Label"] as? String == identifier + ".hardware",
              plist["BundleProgram"] as? String == "Contents/Helpers/HopHardwareHelper.app/Contents/MacOS/HopHardwareHelper",
              plist["Program"] == nil, plist["ProgramArguments"] == nil,
              plist["UserName"] as? String == "root",
              plist["AssociatedBundleIdentifiers"] as? [String] == [identifier],
              let services = plist["MachServices"] as? [String: Bool], services == [identifier + ".hardware": true]
        else { throw HardwareReason.invalid }
    }
}
