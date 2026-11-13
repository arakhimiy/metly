import MetlyCore
import MetlyDesign
import SwiftUI

/// ONB_LANGUAGE — the first screen on a fresh install: 🇺🇿 O‘zbekcha · 🇷🇺 Русский · 🇬🇧 English.
///
/// The screen speaks the highlighted language (title, note and button change as you tap), so
/// someone who opened the app in a language they don't read can still find theirs. Continue applies
/// it to the whole app (`AppPreferences.language`); Settings › Language changes it later.
struct LanguagePickerView: View {
    let onContinue: (AppLanguage) -> Void

    @State private var selection: AppLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initial: AppLanguage = .matching(), onContinue: @escaping (AppLanguage) -> Void) {
        self.onContinue = onContinue
        _selection = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                VStack(spacing: 12) {
                    ForEach(AppLanguage.allCases) { language in
                        LanguageOption(language: language, isSelected: language == selection) {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selection = language }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
        .environment(\.locale, selection.locale)
        .sensoryFeedback(.selection, trigger: selection)
        .bottomActionBar {
            Button { onContinue(selection) } label: {
                Text(verbatim: selection.localized("Continue"))
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .contentTransition(.opacity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text(verbatim: selection.localized("Choose Your Language"))
                .font(.title.bold())   // same size as the welcome titles that follow
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: selection.localized("You can change it later in Settings."))
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .contentTransition(.opacity)
        .frame(maxWidth: .infinity)
    }
}

/// A selectable card: flag, the language's own name and a radio mark. The selected card takes a tinted outline and fill.
private struct LanguageOption: View {
    let language: AppLanguage
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                FlagBadge(flag: language.flag)
                Text(verbatim: language.nativeName)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiaryLabel)))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(background)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // VoiceOver reads each name in its own language.
        .environment(\.locale, language.locale)
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return shape
            .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay(shape.strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2))
    }
}

/// The flag emoji as it is: no crop, no ring.
private struct FlagBadge: View {
    let flag: String

    var body: some View {
        Text(verbatim: flag)
            .font(.system(size: 30))
            .accessibilityHidden(true)
    }
}

private extension AppLanguage {
    var flag: String {
        switch self {
        case .uz: "🇺🇿"
        case .ru: "🇷🇺"
        case .en: "🇬🇧"
        }
    }
}

#Preview("Language · Uzbek") {
    NavigationStack { LanguagePickerView(initial: .uz) { _ in } }
}

#Preview("Language · Russian, dark") {
    NavigationStack { LanguagePickerView(initial: .ru) { _ in } }
        .preferredColorScheme(.dark)
}

#Preview("Language · accessibility size") {
    NavigationStack { LanguagePickerView(initial: .en) { _ in } }
        .dynamicTypeSize(.accessibility3)
}
