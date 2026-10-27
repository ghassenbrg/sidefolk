import Foundation
import SidefolkExtensionKit

/// A quiz with the companion: a question with four answers, then the right one and a fact, and a score that is
/// kept between games. The questions ship with the extension, so it works offline and the AI can't spoil them.
enum Trivia {
    struct Question {
        let category: String
        let text: String
        let choices: [String]
        /// Index of the right choice, as written here (they are shuffled when asked).
        let answer: Int
        let fact: String
    }

    static let bank: [Question] = [
        Question(category: "science", text: "What gas do plants take from the air to make their food?", choices: ["Oxygen", "Carbon dioxide", "Nitrogen", "Helium"],
                 answer: 1, fact: "Photosynthesis turns carbon dioxide and water into sugar, and gives off oxygen."),
        Question(category: "science", text: "What is the chemical symbol for gold?", choices: ["Ag", "Au", "Gd", "Go"],
                 answer: 1, fact: "Au comes from aurum, Latin for gold. Ag is silver."),
        Question(category: "science", text: "How many bones does an adult human have?", choices: ["186", "206", "226", "256"],
                 answer: 1, fact: "Babies are born with around 300; many fuse as they grow."),
        Question(category: "science", text: "What is the hardest natural material?", choices: ["Quartz", "Diamond", "Granite", "Iron"],
                 answer: 1, fact: "Diamond is pure carbon, with every atom bonded to four others."),
        Question(category: "science", text: "At sea level, at what temperature does water boil?", choices: ["90 °C", "100 °C", "110 °C", "120 °C"],
                 answer: 1, fact: "100 °C is 212 °F. On a high mountain it boils lower, because the air pressure is lower."),
        Question(category: "science", text: "Which element has the atomic number 1?", choices: ["Helium", "Hydrogen", "Oxygen", "Carbon"],
                 answer: 1, fact: "Hydrogen is the lightest element and the most common one in the universe."),
        Question(category: "science", text: "Which part of a cell holds most of its DNA?", choices: ["The nucleus", "The ribosomes", "The vacuole", "The cytoplasm"],
                 answer: 0, fact: "Mitochondria carry a little DNA of their own, but most of it is in the nucleus."),
        Question(category: "space", text: "Which planet is called the Red Planet?", choices: ["Venus", "Jupiter", "Mars", "Mercury"],
                 answer: 2, fact: "Mars is red because of iron oxide, rust, in its dust."),
        Question(category: "space", text: "What is the largest planet in our solar system?", choices: ["Saturn", "Jupiter", "Neptune", "Earth"],
                 answer: 1, fact: "More than 1,300 Earths would fit inside Jupiter."),
        Question(category: "space", text: "How long does sunlight take to reach Earth?", choices: ["About 8 seconds", "About 8 minutes", "About 8 hours", "About 8 days"],
                 answer: 1, fact: "About 8 minutes and 20 seconds, across roughly 150 million kilometres."),
        Question(category: "space", text: "Which star is closest to Earth?", choices: ["Proxima Centauri", "The Sun", "Sirius", "Polaris"],
                 answer: 1, fact: "The Sun! After it, the closest is Proxima Centauri, about 4.2 light-years away."),
        Question(category: "space", text: "How many moons does Mars have?", choices: ["None", "One", "Two", "Four"],
                 answer: 2, fact: "Phobos and Deimos, two small moons that may be captured asteroids."),
        Question(category: "space", text: "What is the name of our galaxy?", choices: ["Andromeda", "The Milky Way", "Triangulum", "Sombrero"],
                 answer: 1, fact: "The Milky Way holds hundreds of billions of stars."),
        Question(category: "space", text: "Which planet is famous for its bright rings?", choices: ["Jupiter", "Uranus", "Saturn", "Neptune"],
                 answer: 2, fact: "All four giant planets have rings, but Saturn's are by far the brightest."),
        Question(category: "geography", text: "What is the capital of Australia?", choices: ["Sydney", "Melbourne", "Canberra", "Perth"],
                 answer: 2, fact: "Canberra was built as a compromise between Sydney and Melbourne."),
        Question(category: "geography", text: "What is the capital of Canada?", choices: ["Toronto", "Vancouver", "Ottawa", "Montreal"],
                 answer: 2, fact: "Ottawa is in Ontario, just across the river from Quebec."),
        Question(category: "geography", text: "What is the largest ocean?", choices: ["Atlantic", "Indian", "Arctic", "Pacific"],
                 answer: 3, fact: "The Pacific covers about a third of the Earth's surface."),
        Question(category: "geography", text: "What is the smallest country in the world?", choices: ["Monaco", "Vatican City", "San Marino", "Malta"],
                 answer: 1, fact: "Vatican City covers less than half a square kilometre."),
        Question(category: "geography", text: "Which city lies on two continents?", choices: ["Istanbul", "Cairo", "Moscow", "Athens"],
                 answer: 0, fact: "Istanbul spans the Bosphorus, with parts in Europe and in Asia."),
        Question(category: "geography", text: "What is the largest hot desert?", choices: ["Gobi", "Sahara", "Kalahari", "Atacama"],
                 answer: 1, fact: "Counting cold deserts, Antarctica is the largest desert of all."),
        Question(category: "geography", text: "Mount Everest stands on the border of Nepal and which country?", choices: ["India", "China", "Bhutan", "Pakistan"],
                 answer: 1, fact: "Its northern side is in Tibet, in China."),
        Question(category: "geography", text: "Which of Japan's main islands is Fukuoka on?", choices: ["Honshu", "Kyushu", "Shikoku", "Hokkaido"],
                 answer: 1, fact: "Fukuoka is the largest city on Kyushu, Japan's southwestern main island."),
        Question(category: "geography", text: "What is the capital of Tunisia?", choices: ["Sfax", "Tunis", "Sousse", "Kairouan"],
                 answer: 1, fact: "The country is named after its capital, Tunis."),
        Question(category: "geography", text: "Which is the longest river in South America?", choices: ["Orinoco", "Amazon", "Paraná", "Magdalena"],
                 answer: 1, fact: "The Amazon also carries more water than any other river on Earth."),
        Question(category: "history", text: "In which year did people first walk on the Moon?", choices: ["1965", "1969", "1972", "1975"],
                 answer: 1, fact: "Apollo 11 landed on 20 July 1969."),
        Question(category: "history", text: "Who painted the Mona Lisa?", choices: ["Michelangelo", "Leonardo da Vinci", "Raphael", "Botticelli"],
                 answer: 1, fact: "It hangs in the Louvre, in Paris."),
        Question(category: "history", text: "Ancient Carthage stood in which country of today?", choices: ["Libya", "Tunisia", "Egypt", "Morocco"],
                 answer: 1, fact: "Its ruins are on the coast just outside Tunis."),
        Question(category: "history", text: "Which wall came down in 1989?", choices: ["Hadrian's Wall", "The Great Wall", "The Berlin Wall", "The Western Wall"],
                 answer: 2, fact: "The Berlin Wall opened on 9 November 1989."),
        Question(category: "history", text: "Who first flew alone and nonstop across the Atlantic, in 1927?", choices: ["Amelia Earhart", "Charles Lindbergh", "Orville Wright", "Louis Blériot"],
                 answer: 1, fact: "Amelia Earhart was the first woman to do it, in 1932."),
        Question(category: "history", text: "Who built Europe's first printing press with movable type, around 1440?", choices: ["Johannes Gutenberg", "Galileo Galilei", "Isaac Newton", "William Caxton"],
                 answer: 0, fact: "The Gutenberg Bible, printed in the 1450s, is one of the earliest printed books in Europe."),
        Question(category: "nature", text: "What is the largest animal alive today?", choices: ["African elephant", "Blue whale", "Whale shark", "Giraffe"],
                 answer: 1, fact: "A blue whale's heart alone weighs around 180 kilograms."),
        Question(category: "nature", text: "How many hearts does an octopus have?", choices: ["One", "Two", "Three", "Eight"],
                 answer: 2, fact: "Two pump blood through the gills, one through the rest of the body."),
        Question(category: "nature", text: "What is a baby kangaroo called?", choices: ["A cub", "A joey", "A kit", "A pup"],
                 answer: 1, fact: "A newborn joey is about the size of a jelly bean."),
        Question(category: "nature", text: "What is the fastest land animal?", choices: ["Lion", "Cheetah", "Pronghorn", "Greyhound"],
                 answer: 1, fact: "A cheetah can sprint at around 100 km/h, but only for a short burst."),
        Question(category: "nature", text: "Which of these mammals can truly fly?", choices: ["Flying squirrel", "Bat", "Sugar glider", "Colugo"],
                 answer: 1, fact: "The others glide; bats are the only mammals that fly."),
        Question(category: "nature", text: "How many legs does a spider have?", choices: ["Six", "Eight", "Ten", "Twelve"],
                 answer: 1, fact: "Insects have six; spiders are arachnids, with eight."),
        Question(category: "food", text: "What is the main ingredient of guacamole?", choices: ["Avocado", "Tomato", "Green peas", "Lime"],
                 answer: 0, fact: "Guacamole comes from Mexico; its name comes from the Aztec language, Nahuatl."),
        Question(category: "food", text: "Which nut is marzipan made from?", choices: ["Hazelnut", "Almond", "Walnut", "Peanut"],
                 answer: 1, fact: "Marzipan is ground almonds and sugar."),
        Question(category: "food", text: "Wasabi belongs to the same plant family as which of these?", choices: ["Ginger", "Mustard and horseradish", "Mint", "Seaweed"],
                 answer: 1, fact: "Much \"wasabi\" outside Japan is coloured horseradish."),
        Question(category: "food", text: "How many minutes are there in a day?", choices: ["1,240", "1,440", "1,640", "2,400"],
                 answer: 1, fact: "24 hours times 60 minutes is 1,440."),
        Question(category: "arts", text: "How many strings does a standard guitar have?", choices: ["Four", "Five", "Six", "Seven"],
                 answer: 2, fact: "A standard bass guitar has four."),
        Question(category: "arts", text: "Who wrote Romeo and Juliet?", choices: ["Charles Dickens", "William Shakespeare", "Jane Austen", "Mark Twain"],
                 answer: 1, fact: "Shakespeare wrote it in the 1590s; it is set in Verona."),
        Question(category: "arts", text: "Which composer kept writing music after losing his hearing?", choices: ["Mozart", "Beethoven", "Bach", "Chopin"],
                 answer: 1, fact: "Beethoven wrote his Ninth Symphony when he was almost completely deaf."),
        Question(category: "arts", text: "Haiku poems come from which country?", choices: ["China", "Korea", "Japan", "India"],
                 answer: 2, fact: "A haiku traditionally has three lines of 5, 7 and 5 syllables."),
        Question(category: "arts", text: "Which language has the most native speakers?", choices: ["English", "Spanish", "Mandarin Chinese", "Hindi"],
                 answer: 2, fact: "English has the most speakers once people who learned it as a second language are counted."),
        Question(category: "tech", text: "What does CPU stand for?", choices: ["Central Processing Unit", "Computer Personal Unit", "Core Power Unit", "Central Program Utility"],
                 answer: 0, fact: "The CPU carries out a program's instructions, one after another, billions of times a second."),
        Question(category: "tech", text: "In which year did the first iPhone come out?", choices: ["2005", "2007", "2009", "2010"],
                 answer: 1, fact: "It was announced in January 2007 and went on sale that June."),
        Question(category: "tech", text: "How many bits are in a byte?", choices: ["4", "8", "16", "32"],
                 answer: 1, fact: "Eight bits give 256 different values, from 0 to 255."),
        Question(category: "tech", text: "What does www stand for in a web address?", choices: ["World Wide Web", "Wide World Web", "Web World Wide", "World Web Window"],
                 answer: 0, fact: "Tim Berners-Lee invented the World Wide Web in 1989."),
        Question(category: "sports", text: "How many players does a football (soccer) team have on the field?", choices: ["9", "10", "11", "12"],
                 answer: 2, fact: "Ten outfield players and one goalkeeper."),
        Question(category: "sports", text: "How often are the Summer Olympics usually held?", choices: ["Every 2 years", "Every 3 years", "Every 4 years", "Every 5 years"],
                 answer: 2, fact: "The Tokyo Games of 2020 were the exception: they took place in 2021."),
        Question(category: "sports", text: "In tennis, what is a score of zero called?", choices: ["Nil", "Love", "Duck", "Zero"],
                 answer: 1, fact: "Nobody is sure where \"love\" comes from; one story says the French l'œuf, the egg, for its shape."),
    ]

    static var categories: [String] { Array(Set(bank.map(\.category))).sorted() }
    static var file: String { Paths.data + "/trivia.json" }

    /// The game between calls: the question waiting for an answer (and the order its choices were shown in),
    /// what was asked lately, and the score.
    struct Game: Codable {
        var pending: Int?
        var order: [Int] = []
        var recent: [Int] = []
        var right = 0
        var answered = 0
        var streak = 0
        var best = 0
        /// The category asked for, kept for the questions that follow an answer.
        var category: String?
    }

    static func load() -> Game {
        FileManager.default.contents(atPath: file).flatMap { try? JSONDecoder().decode(Game.self, from: $0) } ?? Game()
    }

    static func save(_ game: Game) {
        if let data = try? JSONEncoder().encode(game) { FileManager.default.createFile(atPath: file, contents: data) }
    }

    static func play(answer: String?, category: String?) throws -> String {
        var game = load()
        var lines: [String] = []
        if let answer, let index = game.pending {
            let question = bank[index]
            let letters = ["A", "B", "C", "D"]
            let picked = letters.firstIndex(of: answer.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: " .)")))
                .map { game.order[$0] } ?? question.choices.firstIndex { $0.lowercased() == answer.lowercased() }
            guard let picked else { throw Problem("Answer with A, B, C or D.") }
            let rightLetter = letters[game.order.firstIndex(of: question.answer)!]
            game.answered += 1
            if picked == question.answer {
                game.right += 1
                game.streak += 1
                game.best = max(game.best, game.streak)
                lines.append("Correct! \(question.fact)")
            } else {
                game.streak = 0
                lines.append("Not quite: it's \(rightLetter), \(question.choices[question.answer]). \(question.fact)")
            }
            lines.append("Score: \(game.right) of \(game.answered)" + (game.streak > 1 ? ", \(game.streak) in a row" : "") + ". Best streak: \(game.best).")
            game.pending = nil
        } else if answer != nil {
            lines.append("There was no question waiting, so here is one.")
        }
        if let category { game.category = category.lowercased() == "any" ? nil : category.lowercased() } else if answer == nil { game.category = nil }
        let wanted = game.category
        if let wanted, !categories.contains(wanted) {
            throw Problem("Categories: \(categories.joined(separator: ", ")).")
        }
        var pool = bank.indices.filter { (wanted == nil || bank[$0].category == wanted) && !game.recent.contains($0) }
        if pool.isEmpty {
            game.recent = []
            pool = bank.indices.filter { wanted == nil || bank[$0].category == wanted }
        }
        let index = pool.randomElement()!
        let question = bank[index]
        game.pending = index
        game.order = Array(question.choices.indices).shuffled()
        game.recent = Array((game.recent + [index]).suffix(bank.count / 2))
        save(game)
        lines.append("Question (\(question.category)): \(question.text)")
        for (letter, choice) in zip(["A", "B", "C", "D"], game.order) { lines.append("\(letter)) \(question.choices[choice])") }
        lines.append("Answer with A, B, C or D. (Don't give the answer away: you don't know it either.)")
        return lines.joined(separator: "\n")
    }
}
