import SidefolkExtensionKit

// Dev Toolbox, an extension that ships with Sidefolk: no permissions, except reading one file a call names.
let ext = Extension(name: "dev-toolbox")

ext.tool("transform", "Transform text",
         "Exact text conversions: format or minify JSON (and say where it's invalid), base64, URL and hex encode/decode, decode "
         + "a JWT (unverified), sha256/sha1/md5 of text, or count characters, words and lines.",
         input: Schema.object([
             "operation": Schema.string("What to do.", oneOf: Toolbox.operations),
             "text": Schema.string("The text.", minLength: 0, maxLength: 100_000),
         ], required: ["operation", "text"])) { args in
    try Toolbox.transform(try args.required("operation"), args.values["text"] as? String ?? "")
}

ext.tool("timestamp", "Convert a timestamp", "Unix time (seconds or milliseconds) to a date in UTC and here, or a date to Unix time; now if not given.",
         input: Schema.object(["value": Schema.string("1730000000, 1730000000000 or 2026-10-28T09:30:00Z.", maxLength: 60)])) { args in
    try Toolbox.timestamp(args.string("value"))
}

ext.tool("generate", "Generate IDs", "New random UUIDs or 256-bit hex tokens.",
         input: Schema.object([
             "kind": Schema.string("What to make.", oneOf: ["uuid", "token"]),
             "count": Schema.integer("How many (1 if not given).", minimum: 1, maximum: 20),
         ], required: ["kind"])) { args in
    try Toolbox.generate(try args.required("kind"), count: args.int("count") ?? 1)
}

ext.tool("checksum", "File checksum", "The SHA-256 (or SHA-1, MD5) of a file, to compare with a published one.",
         input: Schema.object([
             "path": Schema.path("The file, a full path like ~/Downloads/app.dmg."),
             "algorithm": Schema.string("sha256 if not given.", oneOf: ["sha256", "sha1", "md5"]),
         ], required: ["path"])) { args in
    try Toolbox.checksum(try args.required("path"), algorithm: args.string("algorithm") ?? "sha256")
}

await ext.serve()
