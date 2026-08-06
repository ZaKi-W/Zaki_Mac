import SwiftUI

enum HoverIconButtonKind {
    case neutral
    case accent
    case destructive
}

struct HoverIconButtonStyle: ButtonStyle {
    var kind: HoverIconButtonKind = .neutral
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        HoverIconButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            kind: kind,
            size: size
        )
    }
}

private struct HoverIconButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let kind: HoverIconButtonKind
    let size: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        label
            .foregroundStyle(foregroundColor)
            .frame(width: size, height: size)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .scaleEffect(isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .secondary.opacity(0.42) }
        switch kind {
        case .neutral:
            return isHovering ? .primary : .secondary
        case .accent:
            return isHovering ? .accentColor : .secondary
        case .destructive:
            return isHovering ? .red : .secondary
        }
    }

    private var backgroundColor: Color {
        guard isEnabled, isHovering else { return .clear }
        switch kind {
        case .neutral:
            return Color.primary.opacity(isPressed ? 0.13 : 0.08)
        case .accent:
            return Color.accentColor.opacity(isPressed ? 0.18 : 0.11)
        case .destructive:
            return Color.red.opacity(isPressed ? 0.2 : 0.12)
        }
    }
}

struct LifeCard<Content: View>: View {
    private let content: Content
    @State private var isHovering = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        Color(nsColor: .separatorColor)
                            .opacity(isHovering ? 0.9 : 0.55),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: .black.opacity(isHovering ? 0.06 : 0.025),
                radius: isHovering ? 6 : 2,
                y: isHovering ? 2 : 1
            )
            .scaleEffect(isHovering ? 1.004 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

struct LifeCardGrid<Content: View>: View {
    var minimumCardWidth: CGFloat = 260
    private let content: Content

    init(
        minimumCardWidth: CGFloat = 260,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumCardWidth = minimumCardWidth
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: minimumCardWidth, maximum: 460),
                    spacing: 12,
                    alignment: .top
                )
            ],
            alignment: .leading,
            spacing: 12
        ) {
            content
        }
    }
}

struct LifeActionCard: View {
    let title: String
    let message: String
    let systemImage: String
    var tint: Color = .accentColor
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        LifeCard {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            }
        }
    }
}

struct LifeMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                }

                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct LifePrimaryMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

struct LifeRingGaugeCard: View {
    let title: String
    let numerator: Int
    let denominator: Int
    let systemImage: String
    var tint: Color = .accentColor

    private var progress: Double? {
        guard denominator > 0 else { return nil }
        return min(max(Double(numerator) / Double(denominator), 0), 1)
    }

    private var valueText: String {
        guard let progress else { return "—" }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    private var countText: String {
        denominator > 0 ? "\(numerator) / \(denominator)" : "—"
    }

    var body: some View {
        LifeCard {
            HStack(spacing: 16) {
                Gauge(value: progress ?? 0, in: 0...1) {
                    Text(title)
                } currentValueLabel: {
                    Text(valueText)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(progress == nil ? Color.secondary : tint)
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 7) {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)

                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 78)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(
                denominator > 0 ? "\(valueText), \(countText)" : "—"
            )
        }
    }
}

struct LifeChartCard<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Divider()

                content
                    .frame(maxWidth: .infinity, minHeight: 214)
            }
        }
    }
}

struct LifeChartEmptyState: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 214)
        .accessibilityElement(children: .combine)
    }
}

struct LifeSectionHeader: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var showsDivider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsDivider {
                Divider()
            }

            HStack(alignment: .firstTextBaseline) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(.title3.weight(.semibold))
                } else {
                    Text(title)
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.top, showsDivider ? 6 : 0)
    }
}

struct LifeSummarySection<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            Divider()

            content
        }
        .padding(14)
        .background(
            Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                .opacity(0.28),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.72),
                    lineWidth: 0.5
                )
        }
    }
}

struct LifeEmptyCard: View {
    let title: String
    let message: String
    let systemImage: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        LifeCard {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
        }
    }
}

struct LifeStatusPill: View {
    let title: String
    let systemImage: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.25), lineWidth: 0.5)
            }
    }
}

struct LifeSheetFooter: View {
    let cancelTitle: String
    let saveTitle: String
    var saveDisabled = false
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(cancelTitle, action: cancel)
                .keyboardShortcut(.cancelAction)
            Button(saveTitle, action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
        }
        .padding(16)
    }
}

extension Decimal {
    var lifeDoubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

extension Double {
    var lifeDecimalValue: Decimal {
        Decimal(self)
    }
}

enum LifeFormat {
    static func currency(_ value: Decimal) -> String {
        value.formatted(
            .currency(code: "CNY")
                .precision(.fractionLength(0...2))
        )
    }

    static func quantity(_ value: Decimal, unit: String) -> String {
        let number = value.formatted(
            .number.precision(.fractionLength(0...2))
        )
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    static func date(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .omitted) ?? "—"
    }
}
