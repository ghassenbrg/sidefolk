import Foundation
import SidefolkExtensionKit

/// Real randomness from the Mac's generator, so a coin flip is a coin flip and not a model's habit.
enum Chance {
    static func coin(_ count: Int) -> String {
        let flips = (0..<count).map { _ in Bool.random() ? "heads" : "tails" }
        guard count > 1 else { return "It landed on \(flips[0])." }
        let heads = flips.filter { $0 == "heads" }.count
        return "\(flips.joined(separator: ", ")): \(heads) heads and \(count - heads) tails."
    }

    /// "2d6+1", "d20", "3d8-2".
    static func dice(_ notation: String) throws -> String {
        guard let m = notation.lowercased().replacingOccurrences(of: " ", with: "").wholeMatch(of: /(\d{0,2})d(\d{1,3})([+-]\d{1,3})?/),
              let sides = Int(m.2), (2...1000).contains(sides) else {
            throw Problem("Write the dice like 2d6, d20 or 3d8+2.")
        }
        let count = Int(m.1).map { $0 } ?? 1
        guard (1...50).contains(count) else { throw Problem("Roll between 1 and 50 dice at a time.") }
        let bonus = m.3.flatMap { Int($0) } ?? 0
        let rolls = (0..<count).map { _ in Int.random(in: 1...sides) }
        let total = rolls.reduce(0, +) + bonus
        let shown = notation.trimmingCharacters(in: .whitespaces)
        if count == 1, bonus == 0 { return "Rolled \(shown): \(total)." }
        return "Rolled \(shown): \(rolls.map(String.init).joined(separator: " + "))\(bonus == 0 ? "" : bonus > 0 ? " + \(bonus)" : " − \(-bonus)") = \(total)."
    }

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

/// Rock, paper, scissors against the companion, with a running tally.
enum Hands {
    static let moves = ["rock", "paper", "scissors"]
    static var file: String { Paths.data + "/rock-paper-scissors.json" }

    static func play(_ raw: String) throws -> String {
        let move = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard let mine = moves.firstIndex(of: move) ?? moves.firstIndex(where: { $0.hasPrefix(move) && !move.isEmpty }) else {
            throw Problem("Play rock, paper or scissors.")
        }
        let theirs = Int.random(in: 0..<3)
        var tally = FileManager.default.contents(atPath: file).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        let outcome: String
        switch (mine - theirs + 3) % 3 {
        case 0: outcome = "a draw"; tally["draws", default: 0] += 1
        case 1: outcome = "you win"; tally["you", default: 0] += 1
        default: outcome = "I win"; tally["me", default: 0] += 1
        }
        if let data = try? JSONEncoder().encode(tally) { FileManager.default.createFile(atPath: file, contents: data) }
        return "You played \(moves[mine]), I played \(moves[theirs]): \(outcome)! "
            + "So far: you \(tally["you", default: 0]), me \(tally["me", default: 0]), draws \(tally["draws", default: 0])."
    }
}
