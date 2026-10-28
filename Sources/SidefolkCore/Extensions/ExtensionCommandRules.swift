import Foundation

/// What `ManifestValidator` checks in a manifest's commands (D50), so a mistake is a plain message at install
/// rather than a command that quietly never matches.
enum ExtensionCommandRules {
    static let maxCommandsPerTool = 8
    static let maxSentencesPerCommand = 12
    static let maxSentencesPerExtension = 64

    static let maxWordLists = 16
    static let maxWords = 2_000

    static func check(_ m: ExtensionManifest) -> [ValidationIssue] {
        var issues = wordIssues(m.words)
        var seen: [String: String] = [:]
        var total = 0
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
                if command.say.isEmpty || command.say.count > maxSentencesPerCommand {
                    issues.append(ValidationIssue(field: "\(cf).say", message: "must hold 1–\(maxSentencesPerCommand) sentences."))
                }
                var slotSets: Set<Set<String>> = []
                var slots: Set<String> = []
                for (j, sentence) in command.say.enumerated() {
                    total += 1
                    let sf = "\(cf).say[\(j)]"
                    do {
                        let compiled = try CommandSentence(sentence, words: m.words)
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
                if let input = command.input {
                    issues += inputIssues(input, slots: slots, field: "\(cf).input")
                }
            }
        }
        if total > maxSentencesPerExtension {
            issues.append(ValidationIssue(field: "tools", message: "can have at most \(maxSentencesPerExtension) command sentences in all."))
        }
        return issues
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
    private static func inputIssues(_ input: [String: JSONValue], slots: Set<String>, field: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var used: Set<String> = []
        func visit(_ value: JSONValue, _ path: String) {
            switch value {
            case .string(let s):
                if let name = ToolCommands.slotReference(s) {
                    if slots.contains(name) { used.insert(name) } else {
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
