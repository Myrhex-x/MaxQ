//
//  SourceLabels.swift
//  Max Q
//
//  Marks results that are the source itself rather than a report about it: the subject's own
//  site, a government's page, a research paper, a press release. Worked out from the address
//  alone, on this Mac, with nothing looked up. A label says what kind of page it is, not that the
//  page is right: a government page and a press release both speak for whoever published them.
//

import Foundation

nonisolated enum SourceLabel: String, Equatable, Sendable {
    /// The subject's own site (SpaceX's for "Starship").
    case official
    /// A national or local government's page.
    case government
    /// An international public body (the UN, the WHO, the European Union).
    case international
    /// A research paper or preprint.
    case paper
    /// A press release: the publisher's own words.
    case pressRelease

    var title: String {
        switch self {
        case .official: String(localized: "Official site")
        case .government: String(localized: "Government")
        case .international: String(localized: "Public body")
        case .paper: String(localized: "Research paper")
        case .pressRelease: String(localized: "Press release")
        }
    }

    /// What the label means, for its tooltip.
    var explanation: String {
        switch self {
        case .official: String(localized: "The subject's own site: it speaks for itself.")
        case .government: String(localized: "Published by a government.")
        case .international: String(localized: "Published by an international public body.")
        case .paper: String(localized: "A research paper or preprint: the study itself, not a report about it.")
        case .pressRelease: String(localized: "A press release: the publisher's own words, not independent reporting.")
        }
    }

    var icon: MQIcon {
        switch self {
        case .official: .sealCheck
        case .government, .international: .columns
        case .paper: .doc
        case .pressRelease: .envelope
        }
    }
}

nonisolated enum SourceLabels {
    /// The label for `url`, if it's a primary source. `officialHosts` are the subject's own sites
    /// (from its Grokipedia article); `query` catches a search for a site by name ("openai").
    static func label(for url: URL, query: String = "", officialHosts: Set<String> = []) -> SourceLabel? {
        guard let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = url.path.lowercased()

        if officialHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .official }
        if isNavigational(host: host, query: query) { return .official }
        if isPaper(host: host, path: path) { return .paper }
        if isPressRelease(host: host, path: path) { return .pressRelease }
        if internationalHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .international }
        if governmentDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return .government }
        return nil
    }

    /// The site's registered name ("spacex.com", "bbc.co.uk"), for comparing an official site with
    /// a result's host.
    static func registeredDomain(_ host: String) -> String {
        let parts = host.lowercased().split(separator: ".").map(String.init)
        guard parts.count > 2 else { return parts.joined(separator: ".") }
        let twoPart: Set<String> = ["co.uk", "org.uk", "gov.uk", "ac.uk", "com.au", "gov.au", "co.jp", "co.nz", "com.br",
                                    "gouv.fr", "co.in", "gov.in", "com.mx", "co.za", "com.cn", "gov.cn"]
        let lastTwo = parts.suffix(2).joined(separator: ".")
        return twoPart.contains(lastTwo) ? parts.suffix(3).joined(separator: ".") : lastTwo
    }

    /// A search that's a site's name: "openai" or "open ai" for openai.com.
    private static func isNavigational(host: String, query: String) -> Bool {
        let words = query.lowercased().filter { $0.isLetter || $0.isNumber }
        guard words.count >= 3 else { return false }
        let label = registeredDomain(host).split(separator: ".").first.map(String.init) ?? ""
        return !label.isEmpty && label == words
    }

    private static func isPaper(host: String, path: String) -> Bool {
        let hosts: Set<String> = ["arxiv.org", "doi.org", "biorxiv.org", "medrxiv.org", "ssrn.com", "papers.ssrn.com",
                                  "pubmed.ncbi.nlm.nih.gov", "journals.plos.org", "pnas.org", "nejm.org", "jamanetwork.com",
                                  "thelancet.com", "cell.com", "academic.oup.com", "ieeexplore.ieee.org", "dl.acm.org",
                                  "semanticscholar.org", "openreview.net", "aclanthology.org", "frontiersin.org", "mdpi.com",
                                  "iopscience.iop.org", "journals.aps.org", "hal.science", "zenodo.org"]
        if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        let byPath: [(String, String)] = [
            ("nature.com", "/articles/"), ("science.org", "/doi/"), ("sciencedirect.com", "/science/article/"),
            ("link.springer.com", "/article/"), ("onlinelibrary.wiley.com", "/doi/"), ("tandfonline.com", "/doi/"),
            ("ncbi.nlm.nih.gov", "/pmc/articles/"), ("bmj.com", "/content/"), ("jstor.org", "/stable/"),
            ("researchgate.net", "/publication/"), ("sagepub.com", "/doi/"),
        ]
        return byPath.contains { host.hasSuffix($0.0) && path.contains($0.1) }
    }

    private static func isPressRelease(host: String, path: String) -> Bool {
        let wires: Set<String> = ["prnewswire.com", "businesswire.com", "globenewswire.com", "accesswire.com", "newswire.ca",
                                  "einpresswire.com", "prweb.com", "newsfilecorp.com"]
        if wires.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        return path.contains("/press-release") || path.contains("/pressrelease") || path.contains("/press-room/")
            || path.contains("/communiques-de-presse") || path.contains("/communique-de-presse")
    }

    /// Government domains: whole top-level domains (.gov) and governments' own sites.
    private static let governmentDomains: [String] = [
        "gov", "mil", "gov.uk", "gouv.fr", "gc.ca", "canada.ca", "gov.au", "govt.nz", "gob.es", "gob.mx", "bund.de",
        "admin.ch", "gov.in", "go.jp", "gov.br", "gouv.qc.ca", "gov.ie", "gov.it", "overheid.nl", "government.nl",
        "regeringen.se", "gov.sg", "gov.za", "gv.at", "belgium.be", "gouvernement.fr", "elysee.fr", "service-public.fr",
        "assemblee-nationale.fr", "senat.fr", "parliament.uk", "bundesregierung.de", "bundestag.de",
    ]

    private static let internationalHosts: Set<String> = [
        "un.org", "who.int", "europa.eu", "imf.org", "worldbank.org", "oecd.org", "nato.int", "wto.org", "unesco.org",
        "unicef.org", "unhcr.org", "icj-cij.org", "icc-cpi.int", "iaea.org", "ilo.org", "wmo.int", "esa.int",
    ]
}
