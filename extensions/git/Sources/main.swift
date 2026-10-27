import SidefolkExtensionKit

// Git, an extension that ships with Sidefolk: the internet, git (found by name), and one folder per call.
let ext = Extension(name: "git")

ext.tool("clone", "Clone a repository",
         "Clones a public Git repository from an https address into a new folder, for example https://github.com/owner/project "
         + "into ~/git/project. The folder must not exist yet; the folder it goes in must. Private repositories and SSH addresses "
         + "(git@…) can't be cloned here.",
         input: Schema.object([
             "url": Schema.string("The repository's https address.", minLength: 9, maxLength: 2048),
             "destination": Schema.path("The new folder to clone into, a full path like ~/git/project."),
         ], required: ["url", "destination"])) { args in
    try Git.clone(try args.required("url"), into: try args.required("destination"))
}

ext.tool("status", "Repository status",
         "The branch of a Git repository, how far it is ahead of or behind its remote as of the last fetch, and which files are "
         + "changed, staged or new.",
         input: Schema.object(["repository": Schema.path("The repository's folder, a full path like ~/git/project.")], required: ["repository"])) { args in
    try Git.status(try args.required("repository"))
}

ext.tool("pull", "Pull the latest changes",
         "Brings a repository's current branch up to date with its https remote, only when that needs no merge (fast-forward). "
         + "Changes nothing when it would.",
         input: Schema.object(["repository": Schema.path("The repository's folder, a full path like ~/git/project.")], required: ["repository"])) { args in
    try Git.pull(try args.required("repository"))
}

ext.tool("log", "Recent commits", "The latest commits on a repository's current branch: short hash, author, when, and subject.",
         input: Schema.object([
             "repository": Schema.path("The repository's folder, a full path like ~/git/project."),
             "count": Schema.integer("How many commits (10 if not given).", minimum: 1, maximum: 50),
         ], required: ["repository"])) { args in
    try Git.log(try args.required("repository"), count: args.int("count") ?? 10)
}

await ext.serve()
