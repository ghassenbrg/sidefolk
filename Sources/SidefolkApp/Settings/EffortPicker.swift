import SidefolkCore
import SwiftUI

/// One model slot's reasoning effort (D36): the levels its provider and model take, and what is
/// chosen. Nil is "Default", which sends nothing.
struct EffortChoice {
    var levels: [ReasoningEffort]
    var selection: ReasoningEffort?
    /// What the model does when nothing is sent, when the provider says.
    var standard: ReasoningEffort?
    var set: @MainActor @Sendable (ReasoningEffort?) -> Void
}

/// "Effort [Extra high ▾]" under a model field.
struct EffortPicker: View {
    /// The slot it belongs to ("Model", "Think harder"), for VoiceOver.
    var slot: LocalizedStringKey
    var choice: EffortChoice

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("Effort", comment: "Reasoning effort, beside its menu under a model field")
                .font(Theme.Font.caption).foregroundStyle(Theme.inkMuted)
            // A closure, not `choice.set` itself: Swift 6.3 (Xcode 26) crashes turning that function value
            // into Binding's @isolated(any) setter.
            Picker(selection: Binding(get: { choice.selection }, set: { choice.set($0) })) {
                defaultLabel.tag(ReasoningEffort?.none)
                Divider()
                ForEach(choice.levels, id: \.self) { level in
                    Text(verbatim: level.displayName).tag(Optional(level))
                }
            } label: {
                Text("Reasoning effort for “\(Text(slot))”", comment: "The effort menu under a model field")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var defaultLabel: Text {
        guard let standard = choice.standard else {
            return Text("Default", comment: "Reasoning effort: send nothing, so the model uses its own")
        }
        return Text("Default (\(standard.displayName))", comment: "Reasoning effort: send nothing; the model's own level in parentheses")
    }
}
