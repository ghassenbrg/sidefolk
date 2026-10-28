import Foundation

/// The built-in extensions whose program talks to one public service and nothing else (D47). The sandbox can't
/// hold a program to host names (SECURITY §3), so this is Sidefolk's word for its own code: the model chooses what
/// to ask Weather, never where the request goes. Guard lets an "Always allow" for these hold even after outside
/// content was read. Only extensions installed from the app's own Resources count (origin `bundled`, D39), and a
/// test checks every address in each program against the hosts listed here.
public enum BuiltInServices {
    public struct Service: Sendable {
        /// The service's name as the approval card says it, inside a translated sentence: a brand or a site, never a
        /// phrase that needs an article ("It goes only to ecb.europa.eu").
        public let name: String
        /// Every host the program's code may reach.
        public let hosts: [String]
    }

    /// By extension id.
    public static let byExtension: [String: Service] = [
        "dev.sidefolk.weather": Service(name: WeatherProbe.service, hosts: ["api.open-meteo.com", "geocoding-api.open-meteo.com"]),
        "dev.sidefolk.currency": Service(name: "ecb.europa.eu", hosts: ["www.ecb.europa.eu"]),
    ]
}
