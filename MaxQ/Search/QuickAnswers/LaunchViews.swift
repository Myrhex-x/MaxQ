//
//  LaunchViews.swift
//  Max Q
//
//  The launch card on All, under Grok's answer: the next launch's picture, name and status, a
//  countdown that ticks every second when the time is firm (T-minus, then T-plus once it's gone),
//  the rocket, the pad, the orbit, and the next few launches after it. The countdown's digits roll
//  rather than jump.
//

import SwiftUI

struct LaunchModule: View {
    @Bindable var browser: BrowserModel
    let search: GrokSearch

    var body: some View {
        Group {
            switch search.launches {
            case .ready(let launches):
                if let next = launches.first {
                    LaunchCard(launch: next, later: Array(launches.dropFirst().prefix(3)), browser: browser)
                        .padding(.top, 22)
                        .transition(.rise)
                }
            case .loading:
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.hover)
                    .frame(height: 180)
                    .pulsing()
                    .padding(.top, 22)
                    .transition(.opacity)
            case .none, .failed:
                EmptyView()
            }
        }
        .animation(Motion.smooth, value: search.launches)
    }
}

private struct LaunchCard: View {
    let launch: Launch
    let later: [Launch]
    @Bindable var browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Icon(.arrowUpRight, size: 13)
                        Text("Next launch")
                        Text("·").foregroundStyle(Theme.textQuaternary)
                        Text(launch.provider)
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    Text(launch.name)
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        StatusPill(launch: launch)
                        if launch.webcastLive {
                            HStack(spacing: 5) {
                                LiveDot(color: Theme.danger, size: 6)
                                Text("Live now")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    if launch.hasFirmTime {
                        Countdown(target: launch.net)
                            .padding(.top, 4)
                        Text(launch.net.formatted(date: .complete, time: .shortened))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text(String(localized: "No earlier than \(launch.roughDate)"))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 4)
                        Text(launch.precisionName.isEmpty ? String(localized: "The date isn't set yet.") : String(localized: "Rough date: \(launch.precisionName.lowercased())."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let image = launch.image {
                    FillImage(candidates: [image])
                        .frame(width: 150, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                }
            }
            facts
                .padding(.top, 16)
            if let description = launch.missionDescription, !description.isEmpty {
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            HStack(spacing: 8) {
                if let webcast = launch.webcast {
                    Button { openFromResults(webcast, browser: browser) } label: {
                        HStack(spacing: 6) {
                            Icon(.play, size: 13)
                            Text("Watch")
                        }
                    }
                    .pill(.primary, size: .small)
                }
                Button { browser.openMaxQSearch(launch.name, on: .news) } label: {
                    HStack(spacing: 6) {
                        Icon(.doc, size: 14)
                        Text("News about it")
                    }
                }
                .pill(.secondary, size: .small)
                Button { FollowStore.shared.toggle(launch.name) } label: {
                    HStack(spacing: 6) {
                        Icon(FollowStore.shared.isFollowing(launch.name) ? .bellFill : .bell, size: 14)
                        Text(FollowStore.shared.isFollowing(launch.name) ? "Following" : "Follow")
                    }
                }
                .pill(.ghost, size: .small)
            }
            .padding(.top, 14)
            if !later.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("After that")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    ForEach(later) { launch in
                        HStack(spacing: 10) {
                            Text(launch.hasFirmTime ? launch.net.formatted(.dateTime.month(.abbreviated).day()) : launch.roughDate)
                                .font(.system(size: 12.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 84, alignment: .leading)
                            Text(launch.name)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(launch.status)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(.top, 18)
            }
            Text("Launch data from The Space Devs' Launch Library")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textQuaternary)
                .padding(.top, 14)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            fact(String(localized: "Rocket"), launch.rocket)
            fact(String(localized: "Pad"), [launch.pad, launch.location].filter { !$0.isEmpty }.joined(separator: ", "))
            if let orbit = launch.orbit { fact(String(localized: "Orbit"), orbit) }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
    }
}

/// The launch's status, its dot in the status's tone: go, waiting, held, done, failed.
private struct StatusPill: View {
    let launch: Launch

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(launch.statusName.isEmpty ? launch.status : launch.statusName)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Theme.hover))
    }

    private var color: Color {
        switch launch.status.uppercased() {
        case "GO", "SUCCESS", "IN FLIGHT": Theme.success
        case "HOLD", "TBC": Theme.warning
        case "FAILURE", "PARTIAL FAILURE": Theme.danger
        default: Theme.textTertiary
        }
    }
}

/// T-minus days, hours, minutes and seconds, ticking each second; T-plus once it's passed.
private struct Countdown: View {
    let target: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(target.timeIntervalSince(context.date))
            let remaining = abs(seconds)
            let days = remaining / 86_400, hours = remaining % 86_400 / 3_600
            let minutes = remaining % 3_600 / 60, secs = remaining % 60
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(seconds >= 0 ? "T−" : "T+")
                    .font(.mono(16, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                if days > 0 { unit(days, String(localized: "d")) }
                unit(hours, String(localized: "h"))
                unit(minutes, String(localized: "m"))
                unit(secs, String(localized: "s"))
            }
        }
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(String(format: "%02d", value))
                .font(.mono(26, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText(countsDown: true))
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.trailing, 6)
        }
    }
}
