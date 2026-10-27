import SidefolkExtensionKit

// PDF Tools, an extension that ships with Sidefolk: one file or folder per call, nothing else.
let ext = Extension(name: "pdf")
let pages = Schema.string("Pages like 1-3, 5, 8- (all if not given).", maxLength: 100)

ext.tool("pdf_info", "PDF details", "How many pages a PDF has, its paper size, file size, title and author, and whether it has text.",
         input: Schema.object(["path": Schema.path("The PDF, a full path like ~/Documents/report.pdf.")], required: ["path"])) { args in
    try PDFTools.info(try args.required("path"))
}

ext.tool("pdf_text", "Read a PDF's text", "The text of a PDF's pages, up to 20,000 characters at a time.",
         input: Schema.object(["path": Schema.path("The PDF, a full path."), "pages": pages], required: ["path"])) { args in
    try PDFTools.text(try args.required("path"), pages: args.string("pages"))
}

ext.tool("combine_pdfs", "Combine PDFs", "Combines PDFs from one folder, in the order given, into a new PDF in that folder.",
         input: Schema.object([
             "folder": Schema.path("The folder the PDFs are in, a full path like ~/Documents/Taxes."),
             "files": Schema.array(of: Schema.string("A PDF's file name in that folder.", maxLength: 255), "The PDFs, in order.", minItems: 2, maxItems: 50),
             "name": Schema.string("The new PDF's name (Combined if not given).", maxLength: 120),
         ], required: ["folder", "files"])) { args in
    try PDFTools.combine(folder: try args.required("folder"), files: args.strings("files"), name: args.string("name"))
}

ext.tool("extract_pages", "Take pages out of a PDF", "Saves some pages of a PDF as a new PDF beside it; the original stays as it is.",
         input: Schema.object([
             "folder": Schema.path("The folder the PDF is in, a full path."),
             "file": Schema.string("The PDF's file name in that folder.", maxLength: 255),
             "pages": Schema.string("The pages to keep, like 1-3, 5.", maxLength: 100),
         ], required: ["folder", "file", "pages"])) { args in
    try PDFTools.extract(folder: try args.required("folder"), file: try args.required("file"), pages: try args.required("pages"))
}

await ext.serve()
