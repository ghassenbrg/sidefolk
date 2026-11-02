import SidefolkExtensionKit

// A sample of surfaces (docs/EXTENSIONS.md › Surfaces): nothing here is a real add-on, and it isn't in the gallery.
let ext = Extension(name: "scene-sample")
SceneSample.install(on: ext)
await ext.serve()
