import Foundation

/// Pure helpers for interpreting raw IOKit power-source numbers, kept out of
/// SystemStats so the fiddly sign/overflow handling is unit-testable.
public enum PowerMath {
    /// IOKit's battery `Amperage` is negative while discharging, but some
    /// batteries report it as a 32-bit current widened into a 64-bit field
    /// WITHOUT sign extension — so −500 mA arrives as 4_294_966_796. Any raw
    /// value above `Int32.max` is one of these wrapped negatives; subtract 2^32
    /// to recover the true signed current. Values already in Int32 range (normal
    /// charge/discharge readings, including genuine negatives) pass through.
    public static func signedAmperage(_ raw: Int) -> Int {
        raw > Int(Int32.max) ? raw - (1 << 32) : raw
    }

    /// Instantaneous battery power in watts from raw milliamp/millivolt readings.
    /// Positive while charging, negative while discharging.
    public static func batteryWatts(amperage: Int, voltage: Int) -> Double {
        Double(signedAmperage(amperage)) * Double(voltage) / 1_000_000
    }
}
