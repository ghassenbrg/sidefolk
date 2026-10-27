import SidefolkExtensionKit

// Feeds, an extension that ships with Sidefolk (off until switched on): the internet, nothing else.
let ext = Extension(name: "feeds")

ext.tool("read_feed", "Latest posts",
         "The latest posts of a blog, news site or podcast from its RSS or Atom feed. Give the feed's address or just the site's.",
         input: Schema.object([
             "url": Schema.string("The feed's or the site's address, like https://example.com/blog.", maxLength: 2048),
             "count": Schema.integer("How many posts (10 if not given).", minimum: 1, maximum: 30),
         ], required: ["url"])) { args in
    try await Feeds.latest(try args.required("url"), count: args.int("count") ?? 10)
}

ext.watcher("new_post") { settings, state in
    try await Feeds.newPosts(settings, state: state)
}

await ext.serve()
