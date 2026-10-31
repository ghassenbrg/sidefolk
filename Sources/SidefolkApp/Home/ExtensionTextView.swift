import SidefolkCore
import SwiftUI

extension Text {
    /// An extension's own words, which Sidefolk shows verbatim: sizes, paths and addresses kept left to right when
    /// Sidefolk lays out right to left (`BidiText`, D76).
    init(ext text: String) {
        self.init(verbatim: BidiText.shown(text))
    }
}
