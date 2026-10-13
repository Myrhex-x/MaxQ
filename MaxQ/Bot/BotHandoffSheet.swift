//
//  BotHandoffSheet.swift
//  Max Q
//
//  "Send to Grok Bot": writes an email to the Bot's own inbox with the page and an instruction,
//  then hands it to the user's mail app to review and send. Max Q never sends mail itself.
//

import AppKit
import SwiftUI

struct BotHandoffSheet: View {
    @Bindable var browser: BrowserModel
    let handoff: BotHandoff

    @State private var settings = AppSettings.shared
    @State private var instruction = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Icon(.envelope, size: 20)
                    .foregroundStyle(Theme.textSecondary)
                Text("Send to Grok Bot")
                    .font(.heading(20))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(handoff.title.isEmpty ? String(localized: "This page") : handoff.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                Text(AddressSuggestion.displayURL(handoff.url))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.hover))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

            if settings.botEmailIsValid {
                Text("What should your Bot do with it?")
                    .font(.system(size: 12.5, weight: .medium))
                TextField("For example: read this and add the key dates to my calendar", text: $instruction, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(3...6)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.input))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.composerBorder, lineWidth: 1))
                Text("Opens your mail app with the email addressed to \(settings.botEmail). You review it and press Send.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Your Bot has its own email inbox. Ask your Bot to claim it, then paste the address here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillField(placeholder: "…@mail.grokbot.com", text: $settings.botEmail)
                HStack {
                    if GrokBot.isInstalled {
                        Button("Open Grok Bot") { GrokBot.open() }
                            .pill(.outline, size: .small)
                    } else {
                        Button("Get Grok Bot") {
                            browser.openInNewTab(GrokBot.downloadPage)
                            dismiss()
                        }
                        .pill(.outline, size: .small)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .pill(.ghost, size: .regular)
                Button("Open in Mail") { send() }
                    .keyboardShortcut(.defaultAction)
                    .pill(.primary, size: .regular)
                    .disabled(!settings.botEmailIsValid)
            }
        }
        .padding(26)
        .frame(width: 500)
        .background(Theme.surface)
    }

    private func send() {
        guard let url = GrokBot.mailto(address: settings.botEmail, pageTitle: handoff.title,
                                       pageURL: handoff.url, instruction: instruction) else { return }
        if !NSWorkspace.shared.open(url) {
            browser.showToast(String(localized: "No mail app is set up on this Mac."))
        }
        dismiss()
    }
}

/// The first time the Bot's email is picked in a form and Max Q doesn't know the address yet: paste
/// it once, and the field is filled.
struct BotEmailSetupSheet: View {
    let setup: BotEmailSetup

    @State private var settings = AppSettings.shared
    @State private var address = AppSettings.shared.botEmail
    @Environment(\.dismiss) private var dismiss

    private var valid: Bool { AppSettings.isPlausibleEmail(address) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let icon = GrokBot.appIcon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 28, height: 28)
                } else {
                    Icon(.envelope, size: 20).foregroundStyle(Theme.textSecondary)
                }
                Text("Your Grok Bot's email")
                    .font(.heading(20))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Your Bot has its own inbox on mail.grokbot.com. If it doesn't have one yet, ask it to claim one, then paste the address here. Max Q offers it under email fields, so sign-up codes and receipts go to your Bot.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            PillField(placeholder: "…@mail.grokbot.com", text: $address) { save() }
            HStack {
                if GrokBot.isInstalled {
                    Button("Open Grok Bot") { GrokBot.open() }
                        .pill(.outline, size: .small)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .pill(.ghost, size: .regular)
                Button("Save and fill") { save() }
                    .keyboardShortcut(.defaultAction)
                    .pill(.primary, size: .regular)
                    .disabled(!valid)
            }
        }
        .padding(26)
        .frame(width: 480)
        .background(Theme.surface)
    }

    private func save() {
        guard valid else { return }
        settings.botEmail = address.trimmingCharacters(in: .whitespaces)
        dismiss()
        setup.fill()
    }
}
