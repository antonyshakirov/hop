import Foundation
import Security

public enum HardwareIdentity {
    public static let applications = ["com.antonshakirov.minimo", "com.antonshakirov.minimo.dev"]
    public static let helperSuffix = ".hardware-helper"

    public static func requirement(identifier: String, team: String) -> String? {
        let allowed = applications + applications.map { $0 + helperSuffix }
        guard allowed.contains(identifier), team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
        else { return nil }
        return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"\(team)\""
    }

    public static func ownTeam() -> String? {
        var code: SecCode?, staticCode: SecStaticCode?, information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
