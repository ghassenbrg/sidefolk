import Foundation

/// The Kit's own sentences (its problems: a missing argument, a slow program, a server that didn't answer) in every
/// language Sidefolk speaks, so an extension needn't carry them in its `strings/`. Its own tables win when they do.
enum KitWords {
    static func text(_ key: String, _ code: String) -> String? {
        guard let forms = table[key] else { return nil }
        return forms[Localized.normalized(code)]
    }

    static let table: [String: [String: String]] = [
        "“{key}” is missing.": [
            "fr": "« {key} » manque.", "es": "Falta «{key}».", "de": "„{key}“ fehlt.", "it": "Manca «{key}».",
            "pt-BR": "Falta “{key}”.", "ja": "「{key}」がありません。", "ko": "‘{key}’ 값이 없습니다.", "zh-Hans": "缺少“{key}”。",
            "ar": "«{key}» غير موجود.",
        ],
        "Give the full path, like ~/Downloads/photo.jpg.": [
            "fr": "Indiquez le chemin complet, comme ~/Downloads/photo.jpg.", "es": "Indica la ruta completa, como ~/Downloads/photo.jpg.",
            "de": "Gib den vollständigen Pfad an, etwa ~/Downloads/photo.jpg.", "it": "Indica il percorso completo, come ~/Downloads/photo.jpg.",
            "pt-BR": "Informe o caminho completo, como ~/Downloads/photo.jpg.", "ja": "~/Downloads/photo.jpg のように、完全なパスを指定してください。",
            "ko": "~/Downloads/photo.jpg처럼 전체 경로를 입력하세요.", "zh-Hans": "请给出完整路径，例如 ~/Downloads/photo.jpg。",
            "ar": "اكتب المسار الكامل، مثل ~/Downloads/photo.jpg.",
        ],
        "{program} took longer than {seconds} seconds, so it was stopped.": [
            "fr": "{program} a pris plus de {seconds} secondes ; il a été arrêté.", "es": "{program} tardó más de {seconds} segundos, así que se detuvo.",
            "de": "{program} hat länger als {seconds} Sekunden gebraucht und wurde beendet.",
            "it": "{program} ha impiegato più di {seconds} secondi, quindi è stato fermato.",
            "pt-BR": "{program} levou mais de {seconds} segundos, então foi interrompido.", "ja": "{program} が {seconds} 秒を超えたため、停止しました。",
            "ko": "{program}이(가) {seconds}초를 넘겨 중지했습니다.", "zh-Hans": "{program} 用时超过 {seconds} 秒，已被停止。",
            "ar": "استغرق {program} أكثر من {seconds} ثانية، فأُوقف.",
        ],
        "Couldn't reach {host} ({error}). Check the internet connection.": [
            "fr": "Impossible de joindre {host} ({error}). Vérifiez la connexion à Internet.",
            "es": "No se pudo contactar con {host} ({error}). Comprueba la conexión a internet.",
            "de": "{host} war nicht erreichbar ({error}). Prüfe die Internetverbindung.",
            "it": "Impossibile raggiungere {host} ({error}). Controlla la connessione a internet.",
            "pt-BR": "Não foi possível acessar {host} ({error}). Verifique a conexão com a internet.",
            "ja": "{host} に接続できませんでした（{error}）。インターネット接続を確認してください。",
            "ko": "{host}에 연결할 수 없습니다({error}). 인터넷 연결을 확인하세요.", "zh-Hans": "无法连接 {host}（{error}）。请检查互联网连接。",
            "ar": "تعذّر الوصول إلى {host} ({error}). تحقّق من الاتصال بالإنترنت.",
        ],
        "{host} answered with HTTP {status}.": [
            "fr": "{host} a répondu HTTP {status}.", "es": "{host} respondió con HTTP {status}.", "de": "{host} hat mit HTTP {status} geantwortet.",
            "it": "{host} ha risposto con HTTP {status}.", "pt-BR": "{host} respondeu com HTTP {status}.", "ja": "{host} が HTTP {status} を返しました。",
            "ko": "{host}이(가) HTTP {status}(으)로 응답했습니다.", "zh-Hans": "{host} 返回了 HTTP {status}。", "ar": "ردّ {host} برمز HTTP {status}.",
        ],
        "{host} sent something that isn't JSON.": [
            "fr": "{host} a envoyé autre chose que du JSON.", "es": "{host} envió algo que no es JSON.", "de": "{host} hat etwas gesendet, das kein JSON ist.",
            "it": "{host} ha inviato qualcosa che non è JSON.", "pt-BR": "{host} enviou algo que não é JSON.", "ja": "{host} から JSON ではないデータが届きました。",
            "ko": "{host}이(가) JSON이 아닌 데이터를 보냈습니다.", "zh-Hans": "{host} 发送的内容不是 JSON。", "ar": "أرسل {host} محتوى ليس JSON.",
        ],
        "the server": [
            "fr": "le serveur", "es": "el servidor", "de": "der Server", "it": "il server", "pt-BR": "o servidor", "ja": "サーバ", "ko": "서버",
            "zh-Hans": "服务器", "ar": "الخادم",
        ],
        "The server": [
            "fr": "Le serveur", "es": "El servidor", "de": "Der Server", "it": "Il server", "pt-BR": "O servidor", "ja": "サーバ", "ko": "서버",
            "zh-Hans": "服务器", "ar": "الخادم",
        ],
    ]
}
