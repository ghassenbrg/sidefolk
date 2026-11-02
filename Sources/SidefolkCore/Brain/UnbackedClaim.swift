import Foundation

/// A reply's words about what was done, in every language the app speaks: "I've set a reminder", or that something
/// couldn't be saved. gemma on Ollama answered "I'll show you the temperature in Fukuoka every minute" and never called
/// watch.report; the loop then asks the model once more (`found`, loose, since a wrong guess costs one turn). `ReplyCheck`
/// prints a correction the person reads, so it asks for more (`firm`): words about things Sidefolk does, not "I've added
/// comments to the code" (D115). The words models slip into, not all there are, which is why a failed tool is told regardless.
enum UnbackedClaim {
    /// Saying it about a thing Sidefolk handles, whatever else is in the reply.
    private static let firmClaims = compile([
        // English: "I've saved…", "I'll remind you…", "I'm watching…", "Reminder set"
        #"(?<!should )(?<!shall )(?<!can )(?<!could )(?<!may )(?<!if )(?<!when )(?<!did )\b(?:i|i'll|i will|i'm going to|i am going to|i've|i have|i'm|i am)\s+(?:also\s+|now\s+|just\s+|go ahead and\s+)?"#
            + #"(?:sav(?:e|ed|ing) (?:that|this|it|your|the|a)|remind(?:ing|ed)? you|watch(?:ing)? |monitor(?:ing)? |keep(?:ing)? an eye|notify(?:ing)? you|noted\b|not(?:e|ing) (?:that|this|it|down))"#,
        #"^\s*(?:the\s+)?(?:reminder|watch|watcher|note|task|timer|alarm)\s+(?:is\s+|has been\s+)?(?:set|saved|created|added|scheduled|started)\b"#,
        #"^\s*(?:done|all set)[.!]?\s*$"#,
        // French
        #"\bj'ai\s+(?:bien\s+|aussi\s+|déjà\s+)?(?:enregistré|sauvegardé|noté|programmé)\b"#,
        #"\bje\s+(?:vais\s+)?(?:te\s+|vous\s+)?(?:rappellerai|rappeler|surveillerai|surveiller)\b"#,
        #"^\s*(?:le\s+|la\s+)?(?:rappel|note|tâche)\s+(?:est\s+|a été\s+)?(?:enregistrée?|créée?|programmée?|ajoutée?)\b"#,
        #"^\s*(?:c'est fait|terminé)[.!]?\s*$"#,
        // German
        #"\b(?:ich\s+)?habe\b(?:(?!nicht|kein)[^.!?\n]){0,60}?\b(?:gespeichert|notiert|geplant)\b"#,
        #"\bich\s+(?:werde|erinnere)\s+(?:dich|sie)\b"#,
        #"^\s*(?:die\s+)?(?:erinnerung|notiz|aufgabe)\s+(?:ist\s+|wurde\s+)?(?:gesetzt|gespeichert|erstellt|angelegt|hinzugefügt)\b"#,
        #"^\s*(?:erledigt|fertig)[.!]?\s*$"#,
        // Spanish
        #"(?<!\bno )\b(?:guardé|anoté|programé)\b"#,
        #"(?<!\bno )\bhe\s+(?:guardado|anotado|programado)\b"#,
        #"\bte\s+(?:recordaré|avisaré)\b"#,
        #"^\s*(?:el\s+|la\s+)?(?:recordatorio|nota|tarea)\s+(?:está\s+|ha sido\s+)?(?:cread[oa]|guardad[oa]|programad[oa]|configurad[oa]|añadid[oa])\b"#,
        #"^\s*(?:listo|hecho)[.!]?\s*$"#,
        // Portuguese
        #"(?<!não )\b(?:salvei|anotei|agendei)\b"#,
        #"\b(?:vou|irei)\s+(?:te\s+)?(?:lembrar|avisar)\b"#,
        #"\bte\s+(?:lembrarei|avisarei)\b"#,
        #"^\s*(?:o\s+|a\s+)?(?:lembrete|nota|tarefa)\s+(?:foi\s+|está\s+)?(?:criad[oa]|salv[oa]|definid[oa]|agendad[oa]|adicionad[oa])\b"#,
        #"^\s*(?:pronto|feito)[.!]?\s*$"#,
        // Italian
        #"(?<!\bnon )\bho\s+(?:salvato|annotato|programmato)\b"#,
        #"\bti\s+(?:ricorderò|avviserò)\b"#,
        #"^\s*(?:il\s+)?promemoria\s+(?:è\s+stato\s+)?(?:creato|impostato|salvato|aggiunto)\b"#,
        #"^\s*fatto[.!]?\s*$"#,
        // Japanese
        "(?:保存|記録|予約|メモ)(?:し)?(?:ました|済み)",
        "(?:リマインド|監視)(?:し)?ます",
        #"^\s*完了(?:しました)?[。！!]?\s*$"#,
        // Korean
        "(?:저장|기록|예약|메모)(?:했|하였|됐|되었|완료)",
        "(?:알려|리마인드해|감시해)\\s*(?:드릴게요|드리겠습니다)",
        #"^\s*완료(?:했어요|했습니다)?[.!]?\s*$"#,
        // Chinese
        "已(?:经)?(?:保存|记录|记下|安排)",
        "我(?:会|将)(?:提醒|监控|监视)",
        #"^\s*(?:好了|完成了|搞定)[。！!]?\s*$"#,
        // Arabic
        "(?:حفظت|دوّنت|دونت|جدولت)",
        "(?<!لم ي)تم\\s+(?:حفظ|الحفظ|جدولة)",
        "سأذكّرك|سأذكرك|سأراقب",
    ])

    /// Said of anything at all: firm only beside one of `objects`.
    private static let generalClaims = compile([
        #"(?<!should )(?<!shall )(?<!can )(?<!could )(?<!may )(?<!if )(?<!when )(?<!did )\b(?:i|i've|i have)\s+(?:also\s+|now\s+|just\s+)?(?:added|created|set|scheduled|deleted|removed|cancell?ed|stopped)\b"#,
        #"\bj'ai\s+(?:bien\s+|aussi\s+|déjà\s+)?(?:ajouté|créé|planifié|supprimé|annulé|arrêté|mis en place|réglé)\b"#,
        #"\b(?:ich\s+)?habe\b(?:(?!nicht|kein)[^.!?\n]){0,60}?\b(?:hinzugefügt|erstellt|angelegt|eingerichtet|gelöscht|entfernt|gestoppt)\b"#,
        #"(?<!\bno )\b(?:añadí|agregué|creé|configuré|eliminé|borré|cancelé)\b"#,
        #"(?<!\bno )\bhe\s+(?:añadido|agregado|creado|configurado|eliminado|borrado|cancelado)\b"#,
        #"(?<!não )\b(?:adicionei|criei|defini|configurei|removi|apaguei|excluí|cancelei)\b"#,
        #"(?<!\bnon )\bho\s+(?:aggiunto|creato|impostato|eliminato|rimosso|annullato)\b"#,
        "(?:追加|作成|設定|登録|削除|停止)(?:し)?(?:ました|済み)",
        "(?:추가|생성|설정|등록|삭제|중지)(?:했|하였|됐|되었|완료)",
        "已(?:经)?(?:添加|创建|设置|设定|删除|取消|停止)",
        "(?:أضفت|أنشأت|ضبطت|حذفت|ألغيت)",
        "(?<!لم ي)تم\\s+(?:إضافة|الإضافة|إنشاء|ضبط|تعيين|حذف|إلغاء)",
    ])

    /// What Sidefolk keeps: "I added the task", not "I added comments".
    private static let objects = compile([
        #"\b(?:reminders?|notes?|notebook|tasks?|to-?dos?|inbox|lists?|watch(?:er)?s?|timers?|alarms?)\b"#,
        #"\b(?:rappels?|notes?|tâches?|carnet|listes?)\b"#,
        #"\b(?:erinnerung(?:en)?|notizen?|aufgaben?|notizbuch|listen?)\b"#,
        #"\b(?:recordatorios?|notas?|tareas?|cuaderno|listas?)\b"#,
        #"\b(?:lembretes?|notas?|tarefas?|caderno|listas?)\b"#,
        #"\b(?:promemoria|note?|attività|taccuino|liste?)\b"#,
        "リマインダー|メモ|タスク|ノート|リスト",
        "리마인더|메모|할\\s*일|노트|목록",
        "提醒|笔记|任务|清单|列表",
        "تذكير|ملاحظة|مهمة|قائمة|دفتر",
    ])

    /// What only the loop's extra turn listens for: a promise of anything, or a line that starts as done.
    private static let looseClaims = compile([
        #"\b(?:i'll|i will|i'm going to|i am going to|i've|i have|i'm|i am)\s+(?:also\s+|now\s+|just\s+|go ahead and\s+)?"#
            + #"(?:show(?:ing|n)?|display(?:ing|ed)?|remind(?:ing|ed)?|watch(?:ing|ed)?|track(?:ing|ed)?|monitor(?:ing|ed)?|"#
            + #"notify(?:ing)?|notified|alert(?:ing|ed)?|ping(?:ing|ed)?|let you know|keep(?:ing)? (?:an eye|you posted|you updated)|"#
            + #"sav(?:e|ed|ing)|add(?:ed|ing)?|creat(?:e|ed|ing)|set(?:ting)? (?:up |a |an |the |it|you|that|this|your)|"#
            + #"schedul(?:e|ed|ing)|start(?:ed|ing)? (?:a |an |the |watching|showing|tracking|reporting)|not(?:e|ed|ing)|"#
            + #"remember(?:ed|ing)?|report(?:ed|ing)?|turn(?:ed|ing)? (?:on|off)|stopp?(?:ed|ing)? (?:the|it|that|this|your|watching|showing)|"#
            + #"cancel(?:l?ed|l?ing)? (?:the|it|that|this|your)|delet(?:e|ed|ing)|remov(?:e|ed|ing)|sen(?:d|t|ding) (?:you|it|the|a))\b"#,
        #"\b(?:reminder|watch|watcher|note|timer|alarm|report)\s+(?:is\s+|has been\s+)?(?:set|saved|created|added|scheduled|started)\b"#,
        #"^\s*(?:done|all set)\b"#,
    ])

    /// "I couldn't save that": said of something that may well have been done. Not "I didn't add a due date".
    private static let denials = compile([
        #"\b(?:couldn't|could not|can't|cannot|wasn't able to|was unable to|am unable to|unable to|failed to)\s+(?:\w+\s+){0,2}?(?:save|add|create|set|remind|note|schedule|watch|record|store)\b"#,
        #"\b(?:pas pu|impossible d)\b[^.!?\n]{0,30}?(?:enregistr|sauvegard|ajout|cré|not|programm)"#,
        #"\bkonnte\b[^.!?\n]{0,40}?\bnicht\b[^.!?\n]{0,40}?\b(?:gespeichert|speichern|hinzugefügt|hinzufügen|erstellt|erstellen|notiert|notieren)\b"#,
        #"\bno\s+(?:he\s+)?(?:pude|podido|se pudo)\s+(?:guard|añad|agreg|cre|anot|program)\w*"#,
        #"\bnão\s+(?:foi possível|consegui|pude)\s+(?:salv|adicion|cri|anot|agend)\w*"#,
        #"\bnon\s+(?:sono riuscit[oa] a|ho potuto|è stato possibile)\s+(?:salv|aggiun|cre|annot|programm)\w*"#,
        "(?:保存|追加|作成|設定|登録|記録)できませんでした|(?:保存|追加|作成|設定|登録|記録)に失敗",
        "(?:저장|추가|생성|설정|등록|기록)(?:하지\\s*못|할\\s*수\\s*없|에\\s*실패)",
        "(?:无法|未能|没能)(?:保存|添加|创建|设置|记录)|(?:保存|添加|创建|设置|记录)失败",
        "(?:لم\\s+أتمكن من|لم\\s+أستطع|تعذّر|تعذر)\\s*(?:حفظ|إضافة|إنشاء|ضبط)",
    ])

    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        patterns.map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive, .anchorsMatchLines]) }
    }

    /// Worth one more turn from the model.
    static func found(in reply: String) -> Bool {
        matches(looseClaims, reply) || matches(firmClaims, reply) || matches(generalClaims, reply)
    }

    /// Enough to tell the person it isn't so.
    static func firm(in reply: String) -> Bool {
        matches(firmClaims, reply) || (matches(generalClaims, reply) && matches(objects, reply))
    }

    static func denied(in reply: String) -> Bool { matches(denials, reply) }

    private static func matches(_ patterns: [NSRegularExpression], _ reply: String) -> Bool {
        let text = reply.replacingOccurrences(of: "\u{2019}", with: "'")
        let range = NSRange(text.startIndex..., in: text)
        return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    /// Sent as the user's turn, never shown: the model either acts now or says plainly what it can't do.
    static let nudge = """
        Your last reply says something was done or will be done, but no tool that does it succeeded, so it did not happen. \
        If one of your tools does what the user asked, call it now. Otherwise reply again without saying anything \
        was or will be done: say plainly what you can't do, or ask for what you need.
        """
}
