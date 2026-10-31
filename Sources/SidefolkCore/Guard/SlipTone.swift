import Foundation

/// How a permission slip speaks (D84, D71's tone by source): calm when the person asked or Sidefolk's own signed code
/// acts on what Sidefolk's own code returned; firm when another app asks, an extension Sidefolk didn't check, or
/// anything after outside content.
public enum SlipTone: Sendable, Equatable {
    case calm, firm
}

extension ApprovalRequest {
    public var slipTone: SlipTone {
        if let reason = ApprovalReason(self) { return reason.calm ? .calm : .firm }
        switch caller {
        case .user, .agent, .command, .routine: return .calm
        case .extension: return firstParty ? .calm : .firm
        case .external: return .firm
        }
    }

    /// Return says yes only to a calm slip the person's own words started, at normal risk (D58, D84). Everything else
    /// needs ⌘Return or a click: a stray Return typed elsewhere must never allow what another app or outside content
    /// asked for.
    public var takesReturn: Bool {
        slipTone == .calm && answersFromKeys && risk != .high
    }
}
