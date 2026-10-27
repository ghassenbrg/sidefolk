import SidefolkExtensionKit

// Images, an extension that ships with Sidefolk: one file or folder per call, and the Mac's graphics hardware.
let ext = Extension(name: "images")

ext.tool("image_info", "Picture details",
         "A picture's size in pixels, format, file size, when and with what it was taken, and whether it records a location.",
         input: Schema.object(["path": Schema.path("The picture, a full path like ~/Pictures/photo.heic.")], required: ["path"])) { args in
    try Images.info(try args.required("path"))
}

ext.tool("convert_images", "Convert pictures",
         "Makes copies of the pictures in a folder (all of them, or the files named) in another format, smaller, or without "
         + "their location, into a Converted folder inside it. The originals are left as they are.",
         input: Schema.object([
             "folder": Schema.path("The folder the pictures are in, a full path like ~/Pictures/Trip."),
             "files": Schema.array(of: Schema.string("A file name in that folder.", maxLength: 255), "Only these pictures (all of them if not given).",
                                   maxItems: 200),
             "format": Schema.string("The format of the copies (jpeg if not given; same keeps each one's own).", oneOf: ["jpeg", "png", "heic", "tiff", "same"]),
             "max_size": Schema.integer("The longest side of the copies in pixels, to make them smaller.", minimum: 16, maximum: 20_000),
             "quality": Schema.integer("JPEG and HEIC quality from 1 to 100 (85 if not given).", minimum: 1, maximum: 100),
             "remove_location": Schema.boolean("Leave out where each photo was taken (its GPS location)."),
         ], required: ["folder"])) { args in
    try Images.convert(folder: try args.required("folder"), files: args.strings("files"), format: args.string("format") ?? "jpeg",
                       maxSize: args.int("max_size"), quality: args.int("quality") ?? 85, removeLocation: args.bool("remove_location") ?? false)
}

await ext.serve()
