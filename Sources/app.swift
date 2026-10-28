import NookKit
import SwiftUI

@main
struct ClaudeUsage: Nooklet {
    var body: some NookScene {
        FloatingPanel(level: .desktop, position: .topTrailing) {
            UsageView()
        }
    }
}
