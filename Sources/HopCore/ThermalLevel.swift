/// How alarming the machine's heat is right now, as macOS itself judges it.
///
/// A fixed number cannot answer this. Apple publishes no thermal limit, and
/// Apple Silicon runs at 90-100 °C under sustained load by design — a red line
/// at 90 °C called a healthy machine broken, and a green one below 70 °C said
/// nothing about a fanless Mac quietly throttling in a warm room. macOS already
/// weighs the chip, its cooling and the ambient temperature and publishes the
/// verdict through `ProcessInfo.thermalState`, so the row follows that, exactly
/// as the memory row follows the system's memory-pressure signal (Anton,
/// 2026-07-27).
public enum ThermalLevel: Int, Equatable, Sendable {
    case normal
    case warning
    case critical

    /// Maps `ProcessInfo.ThermalState.rawValue` (nominal 0, fair 1, serious 2,
    /// critical 3) onto the three colours the monitor speaks in.
    ///
    /// `fair` stays NORMAL on purpose: it means the fans have picked up, which
    /// is a Mac doing its job rather than a Mac in trouble. Turning the row
    /// yellow there would make the colour meaningless — under any real workload
    /// it would be yellow nearly all the time.
    public static func from(thermalStateRawValue raw: Int) -> ThermalLevel {
        switch raw {
        case 2: return .warning       // serious: sustained throttling
        case 3: return .critical      // critical: the system is shedding work
        default: return .normal       // nominal and fair
        }
    }
}
