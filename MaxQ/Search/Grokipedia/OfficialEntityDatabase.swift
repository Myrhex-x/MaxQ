//
//  OfficialEntityDatabase.swift
//  Max Q
//
//  A local, auditable list of well-known entities (companies, products, people, places) mapped
//  to their official websites, adapted from Searxly. The Grokipedia card uses it to recognize a
//  topic confidently and to offer an "official site" link. Bundled and offline: no network.
//

import Foundation

nonisolated public enum OfficialEntityDatabase {

    // MARK: - Version

    public static let entityDBVersion = "maxq-1"

    // MARK: - Core Data Model

    public enum EntityKind: String, Sendable {
        case company
        case person
        case organization
        case product
        case place
        case website
    }

    public struct OfficialEntity: Sendable {
        /// Primary lookup key (normalized, lower, no fluff). Used for exact + fuzzy.
        public let canonicalKey: String
        /// The URL we should open for this entity (the "official website").
        public let primaryURL: String
        /// Many natural-language aliases that should map here (possessives, descriptive, shorthand).
        public let aliases: [String]
        /// The entity's main website host (e.g. "x.ai").
        public let authorityHost: String?
        /// Offline Grokipedia slug hint for the SERP knowledge panel (e.g. "YouTube", "Elon_Musk").
        public let grokipediaSlug: String?
        /// Entity classification for knowledge-panel layout (company vs person, etc.).
        public let entityKind: EntityKind?
        /// Simple Icons slug for offline bundled brand logo (Resources/BrandIcons/*.svg).
        public let brandIconSlug: String?
        /// Wikidata QID for offline knowledge-panel copy (Resources/WikidataEntities/entities.json).
        public let wikidataQID: String?
        /// Short human-readable note for auditors / future maintainers.
        public let notes: String?

        public init(
            canonicalKey: String,
            primaryURL: String,
            aliases: [String] = [],
            authorityHost: String? = nil,
            grokipediaSlug: String? = nil,
            entityKind: EntityKind? = nil,
            brandIconSlug: String? = nil,
            wikidataQID: String? = nil,
            notes: String? = nil
        ) {
            self.canonicalKey = canonicalKey
            self.primaryURL = primaryURL
            self.aliases = aliases
            self.authorityHost = authorityHost
            self.grokipediaSlug = grokipediaSlug
            self.entityKind = entityKind
            self.brandIconSlug = brandIconSlug
            self.wikidataQID = wikidataQID
            self.notes = notes
        }
    }

    // MARK: - Curated list

    /// Curated, high-confidence entries. Aliases are names people actually type for the entity,
    /// never loose descriptions, because a wrong card is worse than no card.
    public static let all: [OfficialEntity] = [
        // =====================================================================
        // SpaceXAI (xAI) and Grok
        // =====================================================================
        OfficialEntity(
            canonicalKey: "xai",
            primaryURL: "https://x.ai",
            aliases: [
                "x.ai", "xai", "x ai", "xai official", "the xai site",
                "grok", "grok xai", "grok official",
                "elon xai", "elon musk xai"
            ],
            authorityHost: "x.ai",
            grokipediaSlug: "XAI_(company)",
            entityKind: .company,
            brandIconSlug: "xai",
            notes: "SpaceXAI (formerly xAI), maker of Grok."
        ),
        OfficialEntity(
            canonicalKey: "grokipedia",
            primaryURL: "https://grokipedia.com",
            aliases: ["grokipedia", "grok ipedia", "grokipedia official"],
            authorityHost: "grokipedia.com",
            notes: "Grokipedia, SpaceXAI's encyclopedia."
        ),

        // =====================================================================
        // Tesla
        // =====================================================================
        OfficialEntity(
            canonicalKey: "tesla",
            primaryURL: "https://tesla.com",
            aliases: [
                "tesla", "tesla official", "the tesla site", "tesla motors",
                "tesla car", "tesla website", "elon tesla", "musk tesla",
                ],
            authorityHost: "tesla.com",
            grokipediaSlug: "Tesla_Inc",
            entityKind: .company,
            brandIconSlug: "tesla",
            notes: "Tesla main site."
        ),
        OfficialEntity(
            canonicalKey: "tesla developer",
            primaryURL: "https://developer.tesla.com",
            aliases: ["tesla developer", "tesla dev", "tesla api"],
            authorityHost: "developer.tesla.com",
            notes: "Tesla developer / API portal."
        ),

        // =====================================================================
        // SpaceX + Neuralink + broader Musk ecosystem
        // =====================================================================
        OfficialEntity(
            canonicalKey: "spacex",
            primaryURL: "https://spacex.com",
            aliases: ["spacex", "space x", "space-x", "elon spacex", "musk spacex"],
            authorityHost: "spacex.com",
            grokipediaSlug: "SpaceX",
            entityKind: .company,
            notes: "SpaceX official site."
        ),
        OfficialEntity(
            canonicalKey: "neuralink",
            primaryURL: "https://neuralink.com",
            aliases: ["neuralink", "neural link", "elon neuralink", "musk neuralink"],
            authorityHost: "neuralink.com",
            grokipediaSlug: "Neuralink",
            entityKind: .company,
            notes: "Neuralink official site."
        ),
        OfficialEntity(
            canonicalKey: "starlink",
            primaryURL: "https://www.starlink.com",
            aliases: ["starlink", "star link"],
            authorityHost: "www.starlink.com",
            grokipediaSlug: "Starlink",
            entityKind: .product,
            notes: "Starlink (SpaceX satellite internet)."
        ),

        // =====================================================================
        // X (the platform) — historically one of the hardest cases (news articles vs real site)
        // =====================================================================
        OfficialEntity(
            canonicalKey: "x",
            primaryURL: "https://x.com",
            aliases: [
                "x", "x.com", "twitter", "x twitter", "twitter x", "x rebrand",
                "formerly twitter", "the platform formerly known as twitter",
                "x official", "twitter official"
            ],
            authorityHost: "x.com",
            grokipediaSlug: "Twitter",
            entityKind: .website,
            notes: "X (formerly Twitter). Grokipedia article: grokipedia.com/page/Twitter."
        ),

        // =====================================================================
        // Wikipedia + reference (special handling for "the wikipedia page for ...")
        // =====================================================================
        OfficialEntity(
            canonicalKey: "wikipedia",
            primaryURL: "https://wikipedia.org",
            aliases: [
                "wikipedia", "wiki", "the wikipedia site", "wikipedia official",
                "wikipedia page", "wikipedia for"
            ],
            authorityHost: "wikipedia.org",
            notes: "Base Wikipedia. Callers can construct https://en.wikipedia.org/wiki/Topic for 'wikipedia page for Foo'."
        ),
        OfficialEntity(
            canonicalKey: "wikimedia",
            primaryURL: "https://wikimedia.org",
            aliases: ["wikimedia"],
            authorityHost: "wikimedia.org",
            notes: "Wikimedia foundation."
        ),

        // =====================================================================
        // Major well-known brands & services (from original map + staticSuggestions)
        // =====================================================================
        OfficialEntity(
            canonicalKey: "youtube",
            primaryURL: "https://youtube.com",
            aliases: ["youtube", "yt", "youtube official"],
            authorityHost: "youtube.com",
            grokipediaSlug: "YouTube",
            entityKind: .company,
            wikidataQID: "Q866"
        ),
        OfficialEntity(
            canonicalKey: "elon musk",
            primaryURL: "https://x.com/elonmusk",
            aliases: ["elon musk", "elon", "musk"],
            authorityHost: "x.com",
            grokipediaSlug: "Elon_Musk",
            entityKind: .person,
            wikidataQID: "Q317521",
            notes: "Public figure — knowledge panel uses Grokipedia; X profile as optional official link."
        ),

        // =====================================================================
        // Notable people — knowledge panel (Grokipedia + Wikidata + bundled faces)
        // =====================================================================
        OfficialEntity(
            canonicalKey: "bernard arnault",
            primaryURL: "https://www.lvmh.com",
            aliases: ["bernard arnault", "arnault", "bernard jean etienne arnault"],
            authorityHost: "lvmh.com",
            grokipediaSlug: "Bernard_Arnault",
            entityKind: .person,
            wikidataQID: "Q32055",
            notes: "LVMH chairman and CEO — world's leading luxury goods executive."
        ),
        OfficialEntity(
            canonicalKey: "jeff bezos",
            primaryURL: "https://www.aboutamazon.com",
            aliases: ["jeff bezos", "bezos", "jeffrey bezos"],
            authorityHost: "aboutamazon.com",
            grokipediaSlug: "Jeff_Bezos",
            entityKind: .person,
            wikidataQID: "Q312556"
        ),
        OfficialEntity(
            canonicalKey: "bill gates",
            primaryURL: "https://www.gatesfoundation.org",
            aliases: ["bill gates", "gates", "william henry gates"],
            authorityHost: "gatesfoundation.org",
            grokipediaSlug: "Bill_Gates",
            entityKind: .person,
            wikidataQID: "Q5284"
        ),
        OfficialEntity(
            canonicalKey: "mark zuckerberg",
            primaryURL: "https://about.meta.com",
            aliases: ["mark zuckerberg", "zuckerberg", "zuck"],
            authorityHost: "about.meta.com",
            grokipediaSlug: "Mark_Zuckerberg",
            entityKind: .person,
            wikidataQID: "Q36215"
        ),
        OfficialEntity(
            canonicalKey: "warren buffett",
            primaryURL: "https://www.berkshirehathaway.com",
            aliases: ["warren buffett", "buffett", "warren buffet"],
            authorityHost: "berkshirehathaway.com",
            grokipediaSlug: "Warren_Buffett",
            entityKind: .person,
            wikidataQID: "Q47213"
        ),
        OfficialEntity(
            canonicalKey: "steve jobs",
            primaryURL: "https://www.apple.com",
            aliases: ["steve jobs", "jobs"],
            authorityHost: "apple.com",
            grokipediaSlug: "Steve_Jobs",
            entityKind: .person,
            wikidataQID: "Q19837"
        ),
        OfficialEntity(
            canonicalKey: "tim cook",
            primaryURL: "https://www.apple.com",
            aliases: ["tim cook", "timothy cook"],
            authorityHost: "apple.com",
            grokipediaSlug: "Tim_Cook",
            entityKind: .person,
            wikidataQID: "Q265852"
        ),
        OfficialEntity(
            canonicalKey: "jensen huang",
            primaryURL: "https://www.nvidia.com",
            aliases: ["jensen huang", "huang"],
            authorityHost: "nvidia.com",
            grokipediaSlug: "Jensen_Huang",
            entityKind: .person,
            wikidataQID: "Q556445"
        ),
        OfficialEntity(
            canonicalKey: "sam altman",
            primaryURL: "https://openai.com",
            aliases: ["sam altman", "altman"],
            authorityHost: "openai.com",
            grokipediaSlug: "Sam_Altman",
            entityKind: .person,
            wikidataQID: "Q27645609"
        ),
        OfficialEntity(
            canonicalKey: "satya nadella",
            primaryURL: "https://www.microsoft.com",
            aliases: ["satya nadella", "nadella"],
            authorityHost: "microsoft.com",
            grokipediaSlug: "Satya_Nadella",
            entityKind: .person,
            wikidataQID: "Q7426870"
        ),
        OfficialEntity(
            canonicalKey: "larry page",
            primaryURL: "https://about.google",
            aliases: ["larry page", "lawrence page"],
            authorityHost: "about.google",
            grokipediaSlug: "Larry_Page",
            entityKind: .person,
            wikidataQID: "Q167545"
        ),
        OfficialEntity(
            canonicalKey: "sergey brin",
            primaryURL: "https://about.google",
            aliases: ["sergey brin", "brin"],
            authorityHost: "about.google",
            grokipediaSlug: "Sergey_Brin",
            entityKind: .person,
            wikidataQID: "Q92764"
        ),
        OfficialEntity(
            canonicalKey: "donald trump",
            primaryURL: "https://www.donaldjtrump.com",
            aliases: ["donald trump", "trump", "president trump"],
            authorityHost: "donaldjtrump.com",
            grokipediaSlug: "Donald_Trump",
            entityKind: .person,
            wikidataQID: "Q22686"
        ),
        OfficialEntity(
            canonicalKey: "barack obama",
            primaryURL: "https://www.barackobama.com",
            aliases: ["barack obama", "obama", "president obama"],
            authorityHost: "barackobama.com",
            grokipediaSlug: "Barack_Obama",
            entityKind: .person,
            wikidataQID: "Q76"
        ),
        OfficialEntity(
            canonicalKey: "taylor swift",
            primaryURL: "https://www.taylorswift.com",
            aliases: ["taylor swift", "swift"],
            authorityHost: "taylorswift.com",
            grokipediaSlug: "Taylor_Swift",
            entityKind: .person,
            wikidataQID: "Q26876"
        ),
        OfficialEntity(
            canonicalKey: "beyonce",
            primaryURL: "https://www.beyonce.com",
            aliases: ["beyonce", "beyoncé", "beyonce knowles"],
            authorityHost: "beyonce.com",
            grokipediaSlug: "Beyoncé",
            entityKind: .person,
            wikidataQID: "Q36153"
        ),
        OfficialEntity(
            canonicalKey: "lionel messi",
            primaryURL: "https://www.messi.com",
            aliases: ["lionel messi", "messi", "leo messi"],
            authorityHost: "messi.com",
            grokipediaSlug: "Lionel_Messi",
            entityKind: .person,
            wikidataQID: "Q615"
        ),
        OfficialEntity(
            canonicalKey: "cristiano ronaldo",
            primaryURL: "https://www.cristianoronaldo.com",
            aliases: ["cristiano ronaldo", "ronaldo", "cr7"],
            authorityHost: "cristianoronaldo.com",
            grokipediaSlug: "Cristiano_Ronaldo",
            entityKind: .person,
            wikidataQID: "Q11571"
        ),
        OfficialEntity(
            canonicalKey: "francois pinault",
            primaryURL: "https://www.kering.com",
            aliases: ["francois pinault", "françois pinault", "pinault"],
            authorityHost: "kering.com",
            grokipediaSlug: "François_Pinault",
            entityKind: .person,
            wikidataQID: "Q666587"
        ),
        OfficialEntity(
            canonicalKey: "oprah winfrey",
            primaryURL: "https://www.oprah.com",
            aliases: ["oprah winfrey", "oprah"],
            authorityHost: "oprah.com",
            grokipediaSlug: "Oprah_Winfrey",
            entityKind: .person,
            wikidataQID: "Q43303"
        ),

        OfficialEntity(canonicalKey: "youtube music", primaryURL: "https://music.youtube.com", aliases: ["youtube music", "yt music"], authorityHost: "music.youtube.com"),
        OfficialEntity(canonicalKey: "github", primaryURL: "https://github.com", aliases: ["github", "git hub"], authorityHost: "github.com"),
        OfficialEntity(
            canonicalKey: "google",
            primaryURL: "https://google.com",
            aliases: ["google", "google search"],
            authorityHost: "google.com",
            grokipediaSlug: "Google",
            entityKind: .company
        ),
        OfficialEntity(canonicalKey: "gmail", primaryURL: "https://gmail.com", aliases: ["gmail", "google mail"], authorityHost: "gmail.com"),
        OfficialEntity(canonicalKey: "google maps", primaryURL: "https://maps.google.com", aliases: ["google maps", "maps"], authorityHost: "maps.google.com"),
        OfficialEntity(canonicalKey: "reddit", primaryURL: "https://reddit.com", aliases: ["reddit"], authorityHost: "reddit.com"),
        OfficialEntity(canonicalKey: "netflix", primaryURL: "https://netflix.com", aliases: ["netflix"], authorityHost: "netflix.com"),
        OfficialEntity(canonicalKey: "nytimes", primaryURL: "https://nytimes.com", aliases: ["nytimes", "new york times", "nyt"], authorityHost: "nytimes.com"),
        OfficialEntity(canonicalKey: "amazon", primaryURL: "https://amazon.com", aliases: ["amazon", "amazon shopping"], authorityHost: "amazon.com"),
        OfficialEntity(
            canonicalKey: "apple",
            primaryURL: "https://apple.com",
            aliases: ["apple", "apple official", "the apple site"],
            authorityHost: "apple.com",
            grokipediaSlug: "Apple_Inc",
            entityKind: .company
        ),
        OfficialEntity(canonicalKey: "apple developer", primaryURL: "https://developer.apple.com", aliases: ["apple developer", "apple dev", "apple developer portal"], authorityHost: "developer.apple.com"),
        OfficialEntity(canonicalKey: "twitch", primaryURL: "https://twitch.tv", aliases: ["twitch"], authorityHost: "twitch.tv"),
        OfficialEntity(canonicalKey: "discord", primaryURL: "https://discord.com", aliases: ["discord"], authorityHost: "discord.com"),
        OfficialEntity(canonicalKey: "duckduckgo", primaryURL: "https://duckduckgo.com", aliases: ["duckduckgo", "ddg", "duck duck go"], authorityHost: "duckduckgo.com"),
        OfficialEntity(canonicalKey: "facebook", primaryURL: "https://facebook.com", aliases: ["facebook", "fb"], authorityHost: "facebook.com"),
        OfficialEntity(canonicalKey: "figma", primaryURL: "https://figma.com", aliases: ["figma"], authorityHost: "figma.com"),
        OfficialEntity(canonicalKey: "spotify", primaryURL: "https://spotify.com", aliases: ["spotify"], authorityHost: "spotify.com"),
        OfficialEntity(canonicalKey: "stackoverflow", primaryURL: "https://stackoverflow.com", aliases: ["stackoverflow", "stack overflow", "so"], authorityHost: "stackoverflow.com"),
        OfficialEntity(canonicalKey: "steam", primaryURL: "https://store.steampowered.com", aliases: ["steam", "steam store"], authorityHost: "store.steampowered.com"),
        OfficialEntity(canonicalKey: "microsoft", primaryURL: "https://microsoft.com", aliases: ["microsoft", "ms"], authorityHost: "microsoft.com"),
        OfficialEntity(canonicalKey: "medium", primaryURL: "https://medium.com", aliases: ["medium"], authorityHost: "medium.com"),
        OfficialEntity(canonicalKey: "linkedin", primaryURL: "https://linkedin.com", aliases: ["linkedin", "linked in"], authorityHost: "linkedin.com"),
        OfficialEntity(canonicalKey: "chatgpt", primaryURL: "https://chat.openai.com", aliases: ["chatgpt", "chat gpt", "openai chat"], authorityHost: "chat.openai.com"),
        OfficialEntity(canonicalKey: "openai", primaryURL: "https://openai.com", aliases: ["openai", "open ai"], authorityHost: "openai.com"),
        OfficialEntity(canonicalKey: "anthropic", primaryURL: "https://anthropic.com", aliases: ["anthropic", "claude"], authorityHost: "anthropic.com"),
        OfficialEntity(canonicalKey: "cloudflare", primaryURL: "https://cloudflare.com", aliases: ["cloudflare"], authorityHost: "cloudflare.com"),
        OfficialEntity(canonicalKey: "hacker news", primaryURL: "https://news.ycombinator.com", aliases: ["hacker news", "hn", "ycombinator"], authorityHost: "news.ycombinator.com"),
        OfficialEntity(canonicalKey: "gitlab", primaryURL: "https://gitlab.com", aliases: ["gitlab"], authorityHost: "gitlab.com"),
        OfficialEntity(canonicalKey: "docker hub", primaryURL: "https://hub.docker.com", aliases: ["docker hub", "dockerhub"], authorityHost: "hub.docker.com"),
        OfficialEntity(canonicalKey: "mdn", primaryURL: "https://developer.mozilla.org", aliases: ["mdn", "mozilla developer network", "developer mozilla"], authorityHost: "developer.mozilla.org"),
        OfficialEntity(canonicalKey: "arxiv", primaryURL: "https://arxiv.org", aliases: ["arxiv"], authorityHost: "arxiv.org"),
        OfficialEntity(canonicalKey: "bbc", primaryURL: "https://bbc.com", aliases: ["bbc", "bbc news"], authorityHost: "bbc.com"),
        OfficialEntity(canonicalKey: "guardian", primaryURL: "https://theguardian.com", aliases: ["guardian", "the guardian"], authorityHost: "theguardian.com"),
        OfficialEntity(canonicalKey: "reuters", primaryURL: "https://reuters.com", aliases: ["reuters"], authorityHost: "reuters.com"),
        OfficialEntity(canonicalKey: "wolfram", primaryURL: "https://wolframalpha.com", aliases: ["wolfram", "wolfram alpha"], authorityHost: "wolframalpha.com"),
        OfficialEntity(canonicalKey: "instagram", primaryURL: "https://instagram.com", aliases: ["instagram", "ig"], authorityHost: "instagram.com"),
        OfficialEntity(canonicalKey: "tiktok", primaryURL: "https://tiktok.com", aliases: ["tiktok"], authorityHost: "tiktok.com"),
        OfficialEntity(canonicalKey: "whatsapp", primaryURL: "https://web.whatsapp.com", aliases: ["whatsapp", "wa"], authorityHost: "web.whatsapp.com"),
        OfficialEntity(canonicalKey: "zoom", primaryURL: "https://zoom.us", aliases: ["zoom"], authorityHost: "zoom.us"),
        OfficialEntity(canonicalKey: "dropbox", primaryURL: "https://dropbox.com", aliases: ["dropbox"], authorityHost: "dropbox.com"),
        OfficialEntity(canonicalKey: "notion", primaryURL: "https://notion.so", aliases: ["notion"], authorityHost: "notion.so"),
        OfficialEntity(canonicalKey: "linear", primaryURL: "https://linear.app", aliases: ["linear"], authorityHost: "linear.app"),
        OfficialEntity(canonicalKey: "vercel", primaryURL: "https://vercel.com", aliases: ["vercel"], authorityHost: "vercel.com"),
        OfficialEntity(canonicalKey: "stripe", primaryURL: "https://stripe.com", aliases: ["stripe"], authorityHost: "stripe.com"),

        // =====================================================================
        // Additional high-value / common "open the official" entities
        // (expanded for the "huge" coverage goal)
        // =====================================================================
        OfficialEntity(canonicalKey: "github.com", primaryURL: "https://github.com", aliases: ["github.com"]),
        OfficialEntity(canonicalKey: "apple.com", primaryURL: "https://apple.com", aliases: ["apple.com"]),
        OfficialEntity(canonicalKey: "x.com", primaryURL: "https://x.com", aliases: ["x.com"]),
        OfficialEntity(canonicalKey: "developer.apple.com", primaryURL: "https://developer.apple.com", aliases: ["developer.apple.com"]),

        // AI / dev tools that users frequently want the "official site" for
        OfficialEntity(canonicalKey: "huggingface", primaryURL: "https://huggingface.co", aliases: ["huggingface", "hugging face", "hf"], authorityHost: "huggingface.co"),
        OfficialEntity(canonicalKey: "replicate", primaryURL: "https://replicate.com", aliases: ["replicate"], authorityHost: "replicate.com"),
        OfficialEntity(canonicalKey: "perplexity", primaryURL: "https://www.perplexity.ai", aliases: ["perplexity", "perplexity ai"], authorityHost: "www.perplexity.ai"),
        OfficialEntity(canonicalKey: "midjourney", primaryURL: "https://midjourney.com", aliases: ["midjourney", "mj"], authorityHost: "midjourney.com"),
        OfficialEntity(canonicalKey: "cursor", primaryURL: "https://cursor.com", aliases: ["cursor", "cursor ai"], authorityHost: "cursor.com"),
        OfficialEntity(canonicalKey: "v0", primaryURL: "https://v0.dev", aliases: ["v0", "v0 dev", "vercel v0"], authorityHost: "v0.dev"),

        // Common privacy / alternative services
        OfficialEntity(canonicalKey: "protonmail", primaryURL: "https://proton.me/mail", aliases: ["protonmail", "proton mail"], authorityHost: "proton.me"),
        OfficialEntity(canonicalKey: "brave", primaryURL: "https://brave.com", aliases: ["brave", "brave browser"], authorityHost: "brave.com"),
        OfficialEntity(canonicalKey: "signal", primaryURL: "https://signal.org", aliases: ["signal", "signal messenger"], authorityHost: "signal.org"),

        // =====================================================================
        // Special "constructable" seeds (Wikipedia, GitHub, X profiles, etc.)
        // Slugs are built by the caller from the topic.
        // =====================================================================
        OfficialEntity(
            canonicalKey: "wikipedia special",
            primaryURL: "https://en.wikipedia.org",
            aliases: ["wikipedia page for", "the wikipedia page for", "wiki for"],
            notes: "Signal for special-case 'open the wikipedia page for <topic>' handling (construct /wiki/Slug)."
        ),
    ]

    // MARK: - Derived Lookups (fast runtime structures)

    /// Fast exact lookup by canonical key or any alias (after normalization in caller).
    private static let lookupTable: [String: OfficialEntity] = {
        var table: [String: OfficialEntity] = [:]
        for entity in all {
            table[entity.canonicalKey] = entity
            for alias in entity.aliases {
                let norm = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if table[norm] == nil {
                    table[norm] = entity
                }
            }
        }
        return table
    }()

    // MARK: - Lookup

    /// Returns the OfficialEntity for an already-normalized key/alias, if any.
    public static func entity(for normalized: String) -> OfficialEntity? {
        let key = normalized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lookupTable[key]
    }
}
