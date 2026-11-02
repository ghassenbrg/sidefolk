#if DEBUG
import AppKit
import SidefolkCore
import SwiftUI

/// A surface for the UI snapshots: a fictional extension with its frame, shapes, text, keys and an overlay, without a pack
/// (pictures from a pack are checked in the debug app with the sample in `samples/scene-sample`). Drawn at its final state.
enum SampleSurface {
    static func info(_ presentation: SurfaceInfo.Presentation) -> SurfaceInfo {
        SurfaceInfo(extensionId: "dev.sample.lantern-garden", extensionName: "Lantern Garden", surface: "plots", title: "Plant a row", symbol: "leaf",
                    presentation: presentation, width: 400, height: 340, sounds: true)
    }

    static let panelScene: JSONValue = [
        "size": [400, 340],
        "title": "Plant a row",
        "back": true,
        "styles": ["cell": ["type": "shape", "fill": "surface_sunken", "stroke": "line", "corner": 6]],
        "nodes": [
            ["type": "shape", "shape": "path", "w": 276, "h": 58, "x": 104, "y": 12, "fill": "surface_raised", "stroke": "line",
             "path": "M12 0 L264 0 Q276 0 276 12 L276 46 Q276 58 264 58 L12 58 Q0 58 0 46 L0 30 L-10 40 L0 18 L0 12 Q0 0 12 0 Z"],
            ["type": "text", "w": 256, "h": 50, "x": 114, "y": 16, "text": "{companion} says: choose where the first seedlings go.", "size": 14, "weight": "semibold", "lines": 2, "align": "leading"],
            ["type": "companion", "pose": "listening", "w": 76, "h": 76, "x": 14, "y": 4],
            ["type": "grid", "id": "field", "columns": 6, "cell": [40, 40], "gap": 4, "x": 68, "y": 92, "ltr": true, "items": .array((0..<18).map { i in
                i == 8 ? ["type": "group", "children": [["style": "cell", "w": 40, "h": 40, "fill": "win"], ["type": "symbol", "name": "checkmark", "w": 18, "h": 18, "x": 11, "y": 11, "color": "on_accent"]]]
                    : ["style": "cell", "w": 40, "h": 40, "area": ["id": "cell", "value": .string("\(i)"), "label": .string("Cell \(i + 1)")]]
            })],
            ["type": "keyset", "name": "kb", "x": 12, "y": 240, "w": 376, "key": [34, 36], "gap": [4, 4], "rows": [[
                ["key": "a"], ["key": "b"], ["key": "c", "fill": "success_soft"], ["key": "d", "faded": true], ["key": "e"], ["key": "↵", "typed": "return", "spoken": "Send", "w": 60, "fill": "accent", "ink": "on_accent"],
            ]]],
            ["type": "clock", "seconds": 83, "running": false, "w": 70, "h": 22, "x": 165, "y": 298, "size": 14, "weight": "semibold", "design": "mono", "color": "ink_muted"],
        ],
    ]

    static let overlayScene: JSONValue = [
        "size": [200, 180],
        "nodes": [
            ["type": "shape", "shape": "ellipse", "w": 96, "h": 96, "x": 52, "y": 60, "fill": "#FFC93C", "stroke": "#B8860B", "line_width": 4, "shadow": ["radius": 6, "dy": 3]],
            ["type": "symbol", "name": "star.fill", "w": 48, "h": 48, "x": 76, "y": 84, "color": "#B8860B"],
            ["type": "shape", "shape": "capsule", "w": 110, "h": 32, "x": 45, "y": 8, "fill": "surface", "stroke": "line"],
            ["type": "text", "w": 110, "h": 32, "x": 45, "y": 8, "text": "Lucky!", "size": 16, "weight": "heavy", "design": "rounded"],
        ],
    ]

    /// A model showing `scene` with no extension behind it: nothing can be moved in a snapshot.
    static func model(_ presentation: SurfaceInfo.Presentation, scene: JSONValue, companion: NSImage?, failure: Bool = false) async -> SurfaceModel {
        let info = info(presentation)
        let session = SurfaceSession(info: info, host: nil, reduceMotion: true)
        let model = SurfaceModel(info: info, session: session, soundsOn: true)
        model.view.figures = SceneFigures(companion: { _, side, _ in
            var rect = CGRect(x: 0, y: 0, width: side * 2, height: side * 2)
            return companion?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }, companionName: "Mochi")
        model.reduceMotion = { true }
        await model.showForSnapshot((try? SurfaceScene.parse(scene)) ?? SurfaceScene(size: SceneSize(width: 200, height: 100)))
        return model
    }
}
#endif
