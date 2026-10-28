import SwiftUI

struct UsageView: View {
    static let compactModeKey = "claude-usage.is-compact"

    @State private var model = UsageModel()
    @AppStorage(UsageView.compactModeKey) private var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 12) {
            header
            if model.limits.isEmpty, model.errorMessage == nil {
                ProgressView().controlSize(.small)
            }
            ForEach(model.limits) { limit in
                if isCompact {
                    CompactLimitRow(limit: limit)
                } else {
                    LimitRow(limit: limit)
                }
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.system(size: isCompact ? 9 : 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(isCompact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(isCompact ? 10 : 16)
        .frame(width: isCompact ? 180 : 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: isCompact ? 12 : 18, style: .continuous))
        .task { model.startPolling() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Claude Usage")
                .font(.system(size: isCompact ? 11 : 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isCompact ? .secondary : .primary)
            Spacer()
            if let updated = model.lastUpdated, !isCompact {
                Text(updated, format: .dateTime.hour().minute())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HeaderButton(symbol: "arrow.clockwise", help: "Refresh") {
                Task { await model.refresh() }
            }
            .disabled(model.isLoading)
            HeaderButton(
                symbol: isCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                help: isCompact ? "Expand" : "Compact"
            ) {
                withAnimation(.snappy(duration: 0.2)) { isCompact.toggle() }
            }
        }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

private enum UsageTint {
    static let warningThreshold = 70.0
    static let criticalThreshold = 90.0

    static func color(for percent: Double) -> Color {
        if percent >= criticalThreshold { return .red }
        if percent >= warningThreshold { return .yellow }
        return .green
    }
}

private enum ResetFormatter {
    static func remaining(until date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let remainder = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(remainder)m" }
        return "\(remainder)m"
    }
}

private struct LimitRow: View {
    static let barHeight: CGFloat = 6

    let limit: UsageLimit

    var body: some View {
        let tint = UsageTint.color(for: limit.percent)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            UsageBar(fraction: min(limit.percent, 100) / 100, tint: tint, height: Self.barHeight)
            if let resetsAt = limit.resetsAt {
                TimelineView(.everyMinute) { context in
                    Text("Resets in \(ResetFormatter.remaining(until: resetsAt, now: context.date))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CompactLimitRow: View {
    static let labelWidth: CGFloat = 34
    static let percentWidth: CGFloat = 30
    static let barHeight: CGFloat = 4

    let limit: UsageLimit

    var body: some View {
        let tint = UsageTint.color(for: limit.percent)
        HStack(spacing: 6) {
            Text(limit.shortTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            UsageBar(fraction: min(limit.percent, 100) / 100, tint: tint, height: Self.barHeight)
            Text("\(Int(limit.percent.rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(width: Self.percentWidth, alignment: .trailing)
        }
        .help(helpText)
    }

    private var helpText: String {
        guard let resetsAt = limit.resetsAt else { return limit.title }
        return "\(limit.title) · resets in \(ResetFormatter.remaining(until: resetsAt, now: Date()))"
    }
}

private struct UsageBar: View {
    let fraction: Double
    let tint: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: height)
    }
}
