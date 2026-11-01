import Foundation

/// What `ManifestValidator` checks in a manifest's commands (D50), so a mistake is a plain message at install
/// rather than a command that quietly never matches.
enum ExtensionCommandRules {
    static let maxCommandsPerTool = 8
    static let maxSentencesPerCommand = 12
    static let maxSentencesPerExtension = 200
    /// In one language's `strings/` file (D100).
    static let maxSentencesPerLanguage = 400
    static let maxParts = 16
    static let maxCarryWords = 400

    static let maxWordLists = 16
    static let maxWords = 2_000

    static func check(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues = wordIssues(m.words) + choiceIssues(m) + partIssues(m) + carryIssues(m.carry, field: "carry")
        var seen: [String: String] = [:]
        var named: [String: String] = [:]
        var total = 0
        var commandNames: Set<String> = []
        let carry = CommandCarry([m.carry])
        for name in m.tools.keys.sorted() {
            guard let meta = m.tools[name] else { continue }
            let field = "tools.\(name)"
            if meta.ai == false, meta.commands.isEmpty {
                issues.append(ValidationIssue(field: "\(field).ai", message: "is false and the tool has no commands, so nothing can reach it."))
            }
            if meta.commands.count > maxCommandsPerTool {
                issues.append(ValidationIssue(field: "\(field).commands", message: "can have at most \(maxCommandsPerTool) commands."))
            }
            for (i, command) in meta.commands.enumerated() {
                let cf = "\(field).commands[\(i)]"
                if let name = command.name {
                    if name.range(of: ManifestValidator.namePattern, options: .regularExpression) == nil {
                        issues.append(ValidationIssue(field: "\(cf).name", message: "isn't a valid name (lowercase letters, digits and _)."))
                    } else if !commandNames.insert(name).inserted {
                        issues.append(ValidationIssue(field: "\(cf).name", message: "“\(name)” is the name of another command."))
                    }
                }
                let sentencesAllowed = command.names.isEmpty ? 1...maxSentencesPerCommand : 0...maxSentencesPerCommand
                if !sentencesAllowed.contains(command.say.count) {
                    issues.append(ValidationIssue(field: "\(cf).say", message: "must hold 1–\(maxSentencesPerCommand) sentences."))
                }
                var slotSets: Set<Set<String>> = []
                var slots: Set<String> = []
                for (j, sentence) in command.say.enumerated() {
                    total += 1
                    let sf = "\(cf).say[\(j)]"
                    do {
                        let compiled = try CommandSentence(sentence, words: m.words, choices: m.choices)
                        let names = Set(compiled.slots.map(\.name))
                        slotSets.insert(names)
                        slots = names
                        let key = compiled.shape
                        if let other = seen[key] {
                            issues.append(ValidationIssue(field: sf, message: "says the same as \(other)."))
                        } else {
                            seen[key] = sf
                        }
                    } catch {
                        issues.append(ValidationIssue(field: sf, message: error.message))
                    }
                }
                // One `input` serves every sentence, so each must name the same slots.
                if slotSets.count > 1 {
                    issues.append(ValidationIssue(field: "\(cf).say", message: "must name the same slots in every sentence."))
                }
                for (j, spoken) in command.names.enumerated() {
                    total += 1
                    let nf = "\(cf).names[\(j)]"
                    if let why = plain(spoken, longest: CommandSentence.maxLength) {
                        issues.append(ValidationIssue(field: nf, message: why))
                        continue
                    }
                    let residual = carry.residual(spoken)
                    if let other = named[residual] {
                        issues.append(ValidationIssue(field: nf, message: "is the same name as \(other) once its carrying words are out."))
                    } else {
                        named[residual] = nf
                    }
                }
                if command.names.count > maxSentencesPerCommand {
                    issues.append(ValidationIssue(field: "\(cf).names", message: "can hold at most \(maxSentencesPerCommand) names."))
                }
                if !command.with.isEmpty, command.names.isEmpty {
                    issues.append(ValidationIssue(field: "\(cf).with", message: "needs `names`: parts stand around a name."))
                }
                var optional: Set<String> = []
                for part in command.with {
                    guard let meta = m.parts[part] else {
                        issues.append(ValidationIssue(field: "\(cf).with", message: "names “\(part)”, which isn't in `parts`."))
                        continue
                    }
                    optional.formUnion(meta.say.flatMap { (try? CommandSentence("xx \($0)", words: m.words, choices: m.choices))?.slots.map(\.name) ?? [] })
                }
                if let input = command.input {
                    issues += inputIssues(input, slots: slots, optional: optional, field: "\(cf).input")
                }
            }
        }
        if total > maxSentencesPerExtension {
            issues.append(ValidationIssue(field: "tools", message: "can have at most \(maxSentencesPerExtension) command sentences in all."))
        }
        return issues
    }

    /// One line of plain words, without a slot's braces; nil when it is fine.
    private static func plain(_ text: String, longest: Int) -> String? {
        let fine = !text.trimmingCharacters(in: .whitespaces).isEmpty && text.count <= longest && ExtensionText.clean(text) == text
            && !text.contains(where: \.isNewline) && !text.contains("{") && !text.contains("}")
        return fine ? nil : "must be one line of 1–\(longest) characters of plain text, without slots."
    }

    /// Enums: a list of values, each with the words people say for it, named apart from Sidefolk's kinds and word lists.
    private static func choiceIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if m.choices.count > maxWordLists { issues.append(ValidationIssue(field: "choices", message: "can hold at most \(maxWordLists) lists.")) }
        for list in m.choices.keys.sorted() {
            let field = "choices.\(list)"
            if list.range(of: #"^[a-z][a-z0-9_]{0,31}$"#, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid list name (lowercase letters, digits and _)."))
            } else if CommandSlotKind(rawValue: list) != nil || m.words[list] != nil {
                issues.append(ValidationIssue(field: field, message: "has the name of a slot kind or of a list in `words`; choose another."))
            }
            let values = m.choices[list] ?? [:]
            if values.count < 2 || values.count > 32 { issues.append(ValidationIssue(field: field, message: "must have 2–32 values.")) }
            for value in values.keys.sorted() {
                if value.range(of: #"^[a-z][a-z0-9_]{0,31}$"#, options: .regularExpression) == nil {
                    issues.append(ValidationIssue(field: "\(field).\(value)", message: "isn't a valid value (lowercase letters, digits and _)."))
                }
                issues += phraseWordIssues(values[value] ?? [], field: "\(field).\(value)")
            }
        }
        return issues
    }

    static func phraseWordIssues(_ words: [String], field: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if words.isEmpty || words.count > 40 { issues.append(ValidationIssue(field: field, message: "must hold 1–40 words.")) }
        for (i, word) in words.enumerated() where word.isEmpty || word.count > 40 || ExtensionText.clean(word) != word
            || word.trimmingCharacters(in: .whitespaces) != word || word.contains("{") || word.contains("}") {
            issues.append(ValidationIssue(field: "\(field)[\(i)]", message: "must be 1–40 characters of plain text."))
        }
        return issues
    }

    private static func partIssues(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if m.parts.count > maxParts { issues.append(ValidationIssue(field: "parts", message: "can hold at most \(maxParts) parts.")) }
        let vocabulary = CommandVocabulary(manifest: m, strings: nil)
        for name in m.parts.keys.sorted() {
            let field = "parts.\(name)"
            guard let part = m.parts[name] else { continue }
            if name.range(of: ManifestValidator.namePattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid part name (lowercase letters, digits and _)."))
            }
            if part.say.isEmpty || part.say.count > maxSentencesPerCommand {
                issues.append(ValidationIssue(field: "\(field).say", message: "must hold 1–\(maxSentencesPerCommand) phrases."))
            }
            for (i, phrase) in part.say.enumerated() {
                issues += phraseIssues(phrase, vocabulary: vocabulary, field: "\(field).say[\(i)]")
            }
        }
        return issues
    }

    /// A part must compile, and must have something of its own to be found by: words, or a slot that takes only a few.
    static func phraseIssues(_ phrase: String, vocabulary: CommandVocabulary, field: String) -> [ValidationIssue] {
        guard let compiled = CommandPhrase(phrase, vocabulary: vocabulary) else {
            return [ValidationIssue(field: field, message: "isn't a phrase Sidefolk can read: 1–\(CommandSentence.maxLength) characters, slots like {level:level}.")]
        }
        let words = phrase.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
        let hasWords = words.range(of: #"\p{L}"#, options: .regularExpression) != nil
        if !hasWords, compiled.slots.contains(where: { $0.vocabulary == nil }) {
            return [ValidationIssue(field: field, message: "needs a word of its own beside a slot that isn't an enum or a list, like “about {topic:text}”.")]
        }
        return []
    }

    static func carryIssues(_ carry: ExtensionManifest.CarryMeta, field: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if carry.all.count > maxCarryWords { issues.append(ValidationIssue(field: field, message: "can hold at most \(maxCarryWords) words.")) }
        for (i, word) in carry.all.enumerated() where word.isEmpty || word.count > 30 || ExtensionText.clean(word) != word
            || word.contains(where: \.isWhitespace) {
            issues.append(ValidationIssue(field: "\(field)[\(i)]", message: "“\(word.prefix(30))” must be one word of plain text, at most 30 characters."))
        }
        return issues
    }

    /// A language's commands, parts and enums follow the same rules as the manifest's, and say the same thing: each sentence
    /// names only slots its English has, of the same kind.
    static func checkTranslations(_ m: ExtensionManifest, strings: ExtensionStrings?) -> [ValidationIssue] {
        guard let strings else { return [] }
        var issues: [ValidationIssue] = []
        let vocabulary = CommandVocabulary(manifest: m, strings: strings)
        let carry = vocabulary.carry
        let commands = m.tools.values.flatMap(\.commands)
        var allNames: [String: String] = [:]
        for command in commands {
            for spoken in command.names where allNames[carry.residual(spoken)] == nil { allNames[carry.residual(spoken)] = command.name ?? "" }
        }
        for code in ExtensionStrings.languages {
            guard let table = strings.tables[code], code != "en" else { continue }
            let file = "strings/\(code).json"
            var count = 0
            for name in table.commands.keys.sorted() {
                guard let words = table.commands[name], let english = commands.first(where: { $0.name == name }) else { continue }
                let slotNames = Set(english.say.flatMap { (try? CommandSentence($0, words: m.words, choices: m.choices))?.slots.map(\.name) ?? [] })
                for (i, sentence) in words.say.enumerated() {
                    count += 1
                    let field = "\(file).commands.\(name).say[\(i)]"
                    do {
                        let compiled = try CommandSentence(sentence, words: vocabulary.words, choices: vocabulary.choices)
                        if !Set(compiled.slots.map(\.name)).isSubset(of: slotNames) {
                            issues.append(ValidationIssue(field: field, message: "names a slot its English sentence doesn't have."))
                        }
                    } catch {
                        issues.append(ValidationIssue(field: field, message: error.message))
                    }
                }
                for (i, spoken) in words.names.enumerated() {
                    count += 1
                    let field = "\(file).commands.\(name).names[\(i)]"
                    if let why = plain(spoken, longest: CommandSentence.maxLength) { issues.append(ValidationIssue(field: field, message: why)); continue }
                    if english.names.isEmpty { issues.append(ValidationIssue(field: field, message: "translates a name its command doesn't have.")); continue }
                    let residual = carry.residual(spoken)
                    if let owner = allNames[residual], owner != name, residual != "" {
                        issues.append(ValidationIssue(field: field, message: "is the same name as the command “\(owner)” once its carrying words are out."))
                    }
                }
            }
            for name in table.parts.keys.sorted() {
                guard let say = table.parts[name], let english = m.parts[name] else { continue }
                let slotNames = Set(english.say.flatMap { phrase in CommandPhrase(phrase, vocabulary: vocabulary)?.slots.map(\.name) ?? [] })
                for (i, phrase) in say.enumerated() {
                    count += 1
                    let field = "\(file).parts.\(name)[\(i)]"
                    issues += phraseIssues(phrase, vocabulary: vocabulary, field: field)
                    if let compiled = CommandPhrase(phrase, vocabulary: vocabulary), !Set(compiled.slots.map(\.name)).isSubset(of: slotNames) {
                        issues.append(ValidationIssue(field: field, message: "names a slot its English part doesn't have."))
                    }
                }
            }
            for list in table.choices.keys.sorted() {
                for value in (table.choices[list] ?? [:]).keys.sorted() {
                    issues += phraseWordIssues(table.choices[list]?[value] ?? [], field: "\(file).choices.\(list).\(value)")
                }
            }
            if let carryWords = table.carry { issues += carryIssues(carryWords, field: "\(file).carry") }
            if count > maxSentencesPerLanguage {
                issues.append(ValidationIssue(field: file, message: "can hold at most \(maxSentencesPerLanguage) command sentences."))
            }
        }
        return issues
    }

    /// Sentences Sidefolk itself claims, so they never reach this extension: Sidefolk's own words come first (D50, D100). A
    /// warning, never a refusal: the app's words may grow with an update, and that mustn't turn off an extension already here.
    static func ownSentences(_ m: ExtensionManifest, strings: ExtensionStrings?) -> [String] {
        let vocabulary = CommandVocabulary(manifest: m, strings: strings)
        let parser = IntentParser(when: WhenParser())
        var out: [String] = []
        for command in m.tools.values.flatMap(\.commands) {
            let translated = command.name.flatMap { vocabulary.translations[$0] }?.flatMap(\.say) ?? []
            for sentence in command.say + translated {
                guard let compiled = try? CommandSentence(sentence, words: vocabulary.words, choices: vocabulary.choices) else { continue }
                if parser.claimsAsItsOwn(compiled.sample) { out.append(compiled.written) }
            }
        }
        return out.sorted()
    }

    /// Lists of plain words, named apart from Sidefolk's own slot kinds.
    private static func wordIssues(_ words: [String: [String]]) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if words.count > maxWordLists { issues.append(ValidationIssue(field: "words", message: "can hold at most \(maxWordLists) lists.")) }
        if words.values.reduce(0, { $0 + $1.count }) > maxWords {
            issues.append(ValidationIssue(field: "words", message: "can hold at most \(maxWords) words in all."))
        }
        for name in words.keys.sorted() {
            let field = "words.\(name)"
            if name.range(of: #"^[a-z][a-z0-9_]{0,31}$"#, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: field, message: "isn't a valid list name (lowercase letters, digits and _)."))
            } else if CommandSlotKind(rawValue: name) != nil {
                issues.append(ValidationIssue(field: field, message: "is the name of one of Sidefolk's own slot kinds; choose another."))
            }
            let list = words[name] ?? []
            if list.isEmpty { issues.append(ValidationIssue(field: field, message: "is empty.")) }
            for (i, word) in list.enumerated() where word.isEmpty || word.count > 40 || ExtensionText.clean(word) != word
                || word.trimmingCharacters(in: .whitespaces) != word {
                issues.append(ValidationIssue(field: "\(field)[\(i)]", message: "must be 1–40 characters of plain text."))
            }
        }
        return issues
    }

    /// Every "{slot}" is a whole value naming a slot of the sentences, and every slot is used.
    /// `optional` are the parts' slots (D100): the input may name them, and those it doesn't reach the tool by their own name.
    private static func inputIssues(_ input: [String: JSONValue], slots: Set<String>, optional: Set<String> = [], field: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var used: Set<String> = []
        func visit(_ value: JSONValue, _ path: String) {
            switch value {
            case .string(let s):
                if let name = ToolCommands.slotReference(s) {
                    if slots.contains(name) || optional.contains(name) { used.insert(name) } else {
                        issues.append(ValidationIssue(field: path, message: "names {\(name)}, which no sentence has."))
                    }
                } else if s.contains("{") || s.contains("}") {
                    issues.append(ValidationIssue(field: path, message: "can only be a whole slot, like \"{place}\", or plain text without braces."))
                }
            case .array(let items):
                for (i, item) in items.enumerated() { visit(item, "\(path)[\(i)]") }
            case .object:
                issues.append(ValidationIssue(field: path, message: "can't hold an object; give the tool's arguments one level deep."))
            case .null, .bool, .number:
                break
            }
        }
        for key in input.keys.sorted() {
            if key.range(of: ManifestValidator.namePattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: "\(field).\(key)", message: "isn't a valid argument name (lowercase letters, digits and _)."))
            }
            visit(input[key]!, "\(field).\(key)")
        }
        for name in slots.subtracting(used).sorted() {
            issues.append(ValidationIssue(field: field, message: "doesn't use {\(name)}; every slot must go somewhere."))
        }
        return issues
    }
}
