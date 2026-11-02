import Foundation

extension ManifestValidator {
    /// `assets` names one folder directly in the pack; everything in it must be a picture or a sound within the caps.
    func checkAssets(_ m: ExtensionManifest, folder: String, issues: inout [ValidationIssue]) {
        guard let name = m.assets else { return }
        guard name.range(of: #"^[a-z0-9][a-z0-9_-]{0,31}$"#, options: .regularExpression) != nil else {
            issues.append(ValidationIssue(field: "assets", message: "must be the name of one folder in the extension folder (lowercase letters, digits, _ and -), like assets."))
            return
        }
        let path = folder + "/" + name
        guard let st = ExtensionFS.lstat(path), ExtensionFS.isDirectory(st) else {
            issues.append(ValidationIssue(field: "assets", message: "“\(name)” isn't a folder in the extension folder (a link isn't accepted)."))
            return
        }
        let report = PackAssets.check(folder: path)
        for problem in report.problems {
            issues.append(ValidationIssue(field: problem.path.isEmpty ? "assets" : "assets/\(problem.path)", message: problem.message))
        }
    }

    /// A title, a symbol, one of the two ways to stand, a canvas within the caps, and sentences as a game's.
    func checkSurfaces(_ m: ExtensionManifest, issues: inout [ValidationIssue]) {
        if m.surfaces.count > 16 { issues.append(ValidationIssue(field: "surfaces", message: "can declare at most 16 surfaces.")) }
        var seen: [String: String] = [:]
        for name in m.surfaces.keys.sorted() {
            let field = "surfaces.\(name)"
            guard let s = m.surfaces[name] else { continue }
            if name.range(of: Self.namePattern, options: .regularExpression) == nil || name.count > 32 {
                issues.append(ValidationIssue(field: field, message: "isn't a valid surface name (lowercase letters, digits and _, at most 32)."))
            }
            if s.title.isEmpty || s.title.count > 40 || ExtensionText.clean(s.title) != s.title {
                issues.append(ValidationIssue(field: "\(field).title", message: "must be 1–40 characters of plain text."))
            }
            if let symbol = s.symbol, symbol.count > 64 || symbol.range(of: Self.symbolPattern, options: .regularExpression) == nil {
                issues.append(ValidationIssue(field: "\(field).symbol", message: "must be an SF Symbol name, like square.grid.2x2."))
            }
            let (w, h) = s.kind == .panel ? (SurfaceLimits.maxWidth, SurfaceLimits.maxHeight) : (SurfaceLimits.maxOverlayWidth, SurfaceLimits.maxOverlayHeight)
            for (key, value, most) in [("width", s.width, w), ("height", s.height, h)] {
                if let value, !(SurfaceLimits.minSide...most).contains(value) {
                    issues.append(ValidationIssue(field: "\(field).\(key)", message: "must be between \(Int(SurfaceLimits.minSide)) and \(Int(most)) points."))
                }
            }
            // Names and values only: free text from a model must not reach the program by this road (T40).
            if s.arguments.count > 12 { issues.append(ValidationIssue(field: "\(field).arguments", message: "can list at most 12 names.")) }
            for key in s.arguments.keys.sorted() {
                let values = s.arguments[key] ?? []
                if key.range(of: Self.namePattern, options: .regularExpression) == nil {
                    issues.append(ValidationIssue(field: "\(field).arguments.\(key)", message: "isn't a valid name (lowercase letters, digits and _)."))
                }
                if values.isEmpty || values.count > 32 || values.contains(where: { $0.isEmpty || $0.count > 40 || ExtensionText.clean($0) != $0 }) {
                    issues.append(ValidationIssue(field: "\(field).arguments.\(key)", message: "must list 1–32 values of 1–40 characters of plain text."))
                }
            }
            if let key = s.speakerSetting, m.settings.first(where: { $0.key == key })?.type != .switch {
                issues.append(ValidationIssue(field: "\(field).speaker_setting", message: "“\(key)” isn't a switch among its settings."))
            }
            if s.say.count > Self.maxGameSentences {
                issues.append(ValidationIssue(field: "\(field).say", message: "can hold at most \(Self.maxGameSentences) sentences."))
            }
            for (i, sentence) in s.say.enumerated() {
                let sf = "\(field).say[\(i)]"
                do {
                    let compiled = try CommandSentence(sentence)
                    if !compiled.slots.isEmpty {
                        issues.append(ValidationIssue(field: sf, message: "can't have slots: a surface's sentence only opens it."))
                    } else if let other = seen[compiled.shape] {
                        issues.append(ValidationIssue(field: sf, message: "says the same as \(other)."))
                    } else {
                        seen[compiled.shape] = sf
                    }
                } catch {
                    issues.append(ValidationIssue(field: sf, message: error.message))
                }
            }
        }
    }
}
