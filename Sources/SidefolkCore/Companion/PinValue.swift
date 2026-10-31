import Foundation

/// A pin's value at rest beside the companion (D84): the number and its unit alone ("17.2 GB" of "17.2 GB of
/// 24 GB"), so the small corner never shows a value cut with "…". The whole value is in the pin's tip.
public enum PinValue {
    /// The leading number with its unit (up to four letters or a sign: %, °, GB, km/h), or the value as it is when it
    /// doesn't start with a number.
    public static func atRest(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.firstMatch(of: /^[-+−]?\d[\d.,]*(\s?(%|°[CF]?|[\p{L}\/]{1,4})(?=\s|$))?/) else { return trimmed }
        return String(match.output.0)
    }
}
