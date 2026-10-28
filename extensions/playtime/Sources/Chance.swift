import Foundation
import SidefolkExtensionKit

/// Real randomness from the Mac's generator, so a pick is a pick and not a model's habit. Coins, dice and rock, paper,
/// scissors moved to the companion itself (`companion.toss`), which plays them on the desktop.
enum Chance {
    static func number(_ low: Int, _ high: Int) throws -> String {
        guard low <= high else { throw Problem("The lowest number must not be bigger than the highest.") }
        return "Picked \(Int.random(in: low...high)) (from \(low) to \(high))."
    }

    static func pick(_ choices: [String], count: Int) throws -> String {
        guard !choices.isEmpty else { throw Problem("Give the choices to pick from.") }
        guard count <= choices.count else { throw Problem("There are only \(choices.count) choices to pick from.") }
        let picked = Array(choices.shuffled().prefix(count))
        return count == 1 ? "Picked: \(picked[0])." : "Picked, in this order: \(picked.joined(separator: ", "))."
    }
}
