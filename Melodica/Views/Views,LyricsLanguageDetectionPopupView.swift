// Views,LyricsLanguageDetectionPopupView.swift
import SwiftUI

struct LyricsLanguageDetectionPopupView: View {
    let request: LyricsTranslationService.UnresolvedTranslationRequest
    var isLiquidGlass: Bool = false
    
    @ObservedObject private var translationService = LyricsTranslationService.shared
    @State private var selectedLanguage: String = "en"
    
    private var suggestedLanguages: [SourceLanguageOption] {
        LyricsTranslationService.availableLanguages
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isLiquidGlass ? .accentColor : .accent)
                
                Text(LocalizedStringKey("lrc_detect_failed_title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        translationService.dismissUnresolved()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey("lrc_action_dismiss"))
            }
            
            HStack(spacing: 8) {
                Text(LocalizedStringKey("lrc_select_source_prompt"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Picker("", selection: $selectedLanguage) {
                    ForEach(suggestedLanguages) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 170)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        translationService.translateUnresolved(withSourceLanguage: selectedLanguage)
                    }
                }) {
                    Text(LocalizedStringKey("lrc_action_translate"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            Group {
                if isLiquidGlass {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.darkSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
            }
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        .padding(.horizontal, isLiquidGlass ? 12 : 16)
        .padding(.vertical, 6)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear {
            let sysLang = SettingsManager.shared.language
            if sysLang == "en" {
                selectedLanguage = "ja"
            } else {
                selectedLanguage = "en"
            }
        }
    }
}
