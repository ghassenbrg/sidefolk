import Foundation

/// How loud the person is, as the light at the companion's feet shows it while the microphone listens (D84): a few
/// steps, so the light moves with the voice and stays still in a quiet room.
public enum VoiceLevel {
    /// Below this the room is quiet (about -50 dBFS); at the top a raised voice (-6 dBFS).
    static let floor: Double = -50, ceiling: Double = -6
    public static let steps = 8.0

    /// A sample peak (0...1 of full scale) as a step from 0 to 1, in eighths.
    public static func step(_ peak: Float) -> Double {
        guard peak > 0 else { return 0 }
        let decibels = 20 * log10(Double(peak))
        let share = min(max((decibels - floor) / (ceiling - floor), 0), 1)
        return (share * steps).rounded() / steps
    }
}
