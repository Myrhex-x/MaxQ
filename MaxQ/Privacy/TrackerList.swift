//
//  TrackerList.swift
//  Max Q
//
//  The trackers Max Q blocks: analytics, ad and data-broker services that follow people from site
//  to site. Max Q's own list, kept short and conservative: services a page works fine without.
//  Sign-in buttons, video players, payment forms and support chats aren't on it, and a tracker is
//  only blocked when a page loads it from another site (google-analytics.com still works on
//  google-analytics.com).
//

import Foundation

nonisolated struct Tracker: Sendable, Equatable {
    /// The domain, matched with its subdomains ("doubleclick.net" covers "stats.g.doubleclick.net").
    let domain: String
    /// Only addresses on the domain whose path starts like one of these regular expressions (the
    /// Meta Pixel's script, not Facebook's whole SDK). Empty blocks the domain.
    var paths: [String] = []
    /// Who runs it, as the shield's list names it.
    let company: String
}

nonisolated enum TrackerList {
    static let all: [Tracker] = [
        // Google
        Tracker(domain: "google-analytics.com", company: "Google Analytics"),
        Tracker(domain: "googletagmanager.com", company: "Google Tag Manager"),
        Tracker(domain: "googletagservices.com", company: "Google Ads"),
        Tracker(domain: "googlesyndication.com", company: "Google Ads"),
        Tracker(domain: "googleadservices.com", company: "Google Ads"),
        Tracker(domain: "doubleclick.net", company: "Google Ads"),
        Tracker(domain: "adservice.google.com", company: "Google Ads"),
        // Meta, X, Microsoft, LinkedIn, TikTok, Pinterest, Snap, Reddit, Amazon
        Tracker(domain: "connect.facebook.net", paths: ["/[a-zA-Z_]+/fbevents\\.js", "/signals/"], company: "Meta Pixel"),
        Tracker(domain: "facebook.com", paths: ["/tr[/?]"], company: "Meta Pixel"),
        Tracker(domain: "ads-twitter.com", company: "X Ads"),
        Tracker(domain: "analytics.twitter.com", company: "X Ads"),
        Tracker(domain: "bat.bing.com", company: "Microsoft Ads"),
        Tracker(domain: "clarity.ms", company: "Microsoft Clarity"),
        Tracker(domain: "snap.licdn.com", company: "LinkedIn Insight"),
        Tracker(domain: "px.ads.linkedin.com", company: "LinkedIn Insight"),
        Tracker(domain: "analytics.tiktok.com", company: "TikTok Pixel"),
        Tracker(domain: "ct.pinterest.com", company: "Pinterest Tag"),
        Tracker(domain: "s.pinimg.com", paths: ["/ct/"], company: "Pinterest Tag"),
        Tracker(domain: "tr.snapchat.com", company: "Snap Pixel"),
        Tracker(domain: "sc-static.net", paths: ["/scevent\\.min\\.js"], company: "Snap Pixel"),
        Tracker(domain: "redditstatic.com", paths: ["/ads/"], company: "Reddit Pixel"),
        Tracker(domain: "amazon-adsystem.com", company: "Amazon Ads"),
        // Analytics and session recording
        Tracker(domain: "hotjar.com", company: "Hotjar"),
        Tracker(domain: "hotjar.io", company: "Hotjar"),
        Tracker(domain: "mixpanel.com", company: "Mixpanel"),
        Tracker(domain: "mxpnl.com", company: "Mixpanel"),
        Tracker(domain: "cdn.segment.com", company: "Segment"),
        Tracker(domain: "api.segment.io", company: "Segment"),
        Tracker(domain: "amplitude.com", company: "Amplitude"),
        Tracker(domain: "heapanalytics.com", company: "Heap"),
        Tracker(domain: "fullstory.com", company: "FullStory"),
        Tracker(domain: "mouseflow.com", company: "Mouseflow"),
        Tracker(domain: "crazyegg.com", company: "Crazy Egg"),
        Tracker(domain: "luckyorange.com", company: "Lucky Orange"),
        Tracker(domain: "luckyorange.net", company: "Lucky Orange"),
        Tracker(domain: "quantserve.com", company: "Quantcast"),
        Tracker(domain: "quantcount.com", company: "Quantcast"),
        Tracker(domain: "scorecardresearch.com", company: "Comscore"),
        Tracker(domain: "chartbeat.com", company: "Chartbeat"),
        Tracker(domain: "chartbeat.net", company: "Chartbeat"),
        Tracker(domain: "nr-data.net", company: "New Relic"),
        Tracker(domain: "js-agent.newrelic.com", company: "New Relic"),
        Tracker(domain: "mc.yandex.ru", company: "Yandex Metrica"),
        Tracker(domain: "mc.yandex.com", company: "Yandex Metrica"),
        Tracker(domain: "hm.baidu.com", company: "Baidu Analytics"),
        Tracker(domain: "hs-analytics.net", company: "HubSpot"),
        Tracker(domain: "track.hubspot.com", company: "HubSpot"),
        Tracker(domain: "munchkin.marketo.net", company: "Marketo"),
        Tracker(domain: "pi.pardot.com", company: "Salesforce Pardot"),
        Tracker(domain: "omtrdc.net", company: "Adobe Analytics"),
        Tracker(domain: "demdex.net", company: "Adobe Audience Manager"),
        Tracker(domain: "everesttech.net", company: "Adobe Advertising"),
        // Ad exchanges, measurement and data brokers
        Tracker(domain: "adnxs.com", company: "Xandr"),
        Tracker(domain: "adsrvr.org", company: "The Trade Desk"),
        Tracker(domain: "rubiconproject.com", company: "Magnite"),
        Tracker(domain: "pubmatic.com", company: "PubMatic"),
        Tracker(domain: "openx.net", company: "OpenX"),
        Tracker(domain: "casalemedia.com", company: "Index Exchange"),
        Tracker(domain: "indexww.com", company: "Index Exchange"),
        Tracker(domain: "criteo.com", company: "Criteo"),
        Tracker(domain: "criteo.net", company: "Criteo"),
        Tracker(domain: "taboola.com", company: "Taboola"),
        Tracker(domain: "outbrain.com", company: "Outbrain"),
        Tracker(domain: "moatads.com", company: "Oracle Moat"),
        Tracker(domain: "doubleverify.com", company: "DoubleVerify"),
        Tracker(domain: "adsafeprotected.com", company: "Integral Ad Science"),
        Tracker(domain: "teads.tv", company: "Teads"),
        Tracker(domain: "smartadserver.com", company: "Equativ"),
        Tracker(domain: "adform.net", company: "Adform"),
        Tracker(domain: "bidswitch.net", company: "BidSwitch"),
        Tracker(domain: "yieldmo.com", company: "Yieldmo"),
        Tracker(domain: "sharethrough.com", company: "Sharethrough"),
        Tracker(domain: "3lift.com", company: "TripleLift"),
        Tracker(domain: "media.net", company: "Media.net"),
        Tracker(domain: "gumgum.com", company: "GumGum"),
        Tracker(domain: "lijit.com", company: "Sovrn"),
        Tracker(domain: "33across.com", company: "33Across"),
        Tracker(domain: "spotxchange.com", company: "SpotX"),
        Tracker(domain: "springserve.com", company: "SpringServe"),
        Tracker(domain: "zemanta.com", company: "Outbrain"),
        Tracker(domain: "revcontent.com", company: "Revcontent"),
        Tracker(domain: "mgid.com", company: "MGID"),
        Tracker(domain: "adroll.com", company: "AdRoll"),
        Tracker(domain: "advertising.com", company: "Yahoo Ads"),
        Tracker(domain: "ads.yahoo.com", company: "Yahoo Ads"),
        Tracker(domain: "analytics.yahoo.com", company: "Yahoo Analytics"),
        Tracker(domain: "krxd.net", company: "Salesforce DMP"),
        Tracker(domain: "bluekai.com", company: "Oracle BlueKai"),
        Tracker(domain: "exelator.com", company: "Nielsen"),
        Tracker(domain: "imrworldwide.com", company: "Nielsen"),
        Tracker(domain: "rlcdn.com", company: "LiveRamp"),
        Tracker(domain: "agkn.com", company: "Neustar"),
        Tracker(domain: "mathtag.com", company: "MediaMath"),
        Tracker(domain: "crwdcntrl.net", company: "Lotame"),
        Tracker(domain: "tapad.com", company: "Tapad"),
        Tracker(domain: "liadm.com", company: "LiveIntent"),
        Tracker(domain: "id5-sync.com", company: "ID5"),
        Tracker(domain: "bounceexchange.com", company: "Wunderkind"),
        Tracker(domain: "dotomi.com", company: "Conversant"),
        Tracker(domain: "turn.com", company: "Amobee"),
        Tracker(domain: "serving-sys.com", company: "Sizmek"),
    ]

    /// The tracker an address belongs to, if any.
    static func tracker(for url: URL) -> Tracker? {
        let address = url.absoluteString
        return patterns.first { pattern in
            pattern.regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) != nil
        }?.tracker
    }

    /// Each tracker's address patterns, as WebKit's rules and the page's count both use them.
    static let patterns: [(filter: String, regex: NSRegularExpression, tracker: Tracker)] = all.flatMap { tracker in
        let domain = NSRegularExpression.escapedPattern(for: tracker.domain)
        let tails = tracker.paths.isEmpty ? ["[/:?]"] : tracker.paths
        return tails.compactMap { tail in
            let filter = "^https?://([^/]+\\.)?\(domain)\(tail)"
            return (try? NSRegularExpression(pattern: filter, options: [.caseInsensitive])).map { (filter, $0, tracker) }
        }
    }

    /// WebKit's content-blocker rules: each tracker blocked when a page loads it from another site,
    /// then the sites the user lets through.
    static func rules(allowing sites: [String]) -> String {
        var rules: [[String: Any]] = patterns.map { pattern in
            ["trigger": ["url-filter": pattern.filter, "load-type": ["third-party"]], "action": ["type": "block"]]
        }
        if !sites.isEmpty {
            rules.append([
                "trigger": ["url-filter": ".*", "if-domain": sites.map { "*" + $0 }],
                "action": ["type": "ignore-previous-rules"],
            ])
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
