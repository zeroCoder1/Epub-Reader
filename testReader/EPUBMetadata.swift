//
//  EPUBMetadata.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//


import Foundation

struct EPUBMetadata {
    let title: String
    let author: String
    let coverImageURL: URL?
    // dc:identifier from the OPF (e.g. a UUID or ISBN). Used to key per-book
    // persistence so state survives renaming the file. nil when the OPF omits it.
    let identifier: String?
    // Additional Dublin Core metadata; nil when the OPF omits the element.
    let language: String?
    let publisher: String?
    let bookDescription: String?
    let publicationDate: String?
    // Book-level rendition:spread (none/landscape/portrait/both/auto); nil ⇒ default (auto).
    let renditionSpread: String?

    init(title: String, author: String, coverImageURL: URL?, identifier: String?,
         language: String? = nil, publisher: String? = nil,
         bookDescription: String? = nil, publicationDate: String? = nil,
         renditionSpread: String? = nil) {
        self.title = title
        self.author = author
        self.coverImageURL = coverImageURL
        self.identifier = identifier
        self.language = language
        self.publisher = publisher
        self.bookDescription = bookDescription
        self.publicationDate = publicationDate
        self.renditionSpread = renditionSpread
    }
}

// Last-read location within a book, persisted so the reader reopens where it left off.
struct ReadingPosition: Codable {
    let spineIndex: Int
    let pageNumber: Int
    let date: Date
}

// Which half of a two-page spread a fixed-layout page occupies (rendition:page-spread-*).
// .center means the page stands alone (e.g. a cover). .auto lets the reader decide by order.
enum PageSpread: String, Codable {
    case left, right, center, auto
}

// A fixed-layout viewing unit: one page (right == nil) or two side-by-side pages.
struct Spread {
    let left: Int
    let right: Int?
}

struct EPUBSpineItem {
    let id: String
    let href: String
    // false when the itemref carries linear="no" (supplementary content such as
    // endnotes/pop-ups): kept in the spine for link/TOC resolution and index stability,
    // but skipped by the primary page-turn sequence and page-count math.
    let linear: Bool
    // true for pre-paginated (fixed-layout) content — the page is authored to an exact
    // viewport and must be scaled to fit rather than reflowed into columns.
    let isFixedLayout: Bool
    // Which side of a spread this page sits on (fixed-layout only); used for pairing pages.
    let pageSpread: PageSpread

    init(id: String, href: String, linear: Bool = true, isFixedLayout: Bool = false, pageSpread: PageSpread = .auto) {
        self.id = id
        self.href = href
        self.linear = linear
        self.isFixedLayout = isFixedLayout
        self.pageSpread = pageSpread
    }
}

struct EPUBTOCItem {
    let label: String
    let href: String
}

struct Bookmark: Codable {
    let spineIndex: Int
    let pageNumber: Int
    let date: Date
    
    // Computed property for display in bookmarks list
    var displayText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "Page \(pageNumber + 1) - \(formatter.string(from: date))"
    }
}

struct Highlight: Codable {
    let spineIndex: Int
    let pageNumber: Int
    let text: String
    let range: NSRange
    let color: String
    let date: Date
    let textContext: String // Store surrounding text for better matching
    let relativePosition: Double // Position as percentage of spine content
    let startOffset: Int? // Absolute UTF-16 offset of the selection start in the spine's textContent

    init(spineIndex: Int, pageNumber: Int, text: String, range: NSRange, color: String, textContext: String = "", relativePosition: Double = 0.0, startOffset: Int? = nil) {
        self.spineIndex = spineIndex
        self.pageNumber = pageNumber
        self.text = text
        self.range = range
        self.color = color
        self.date = Date()
        self.textContext = textContext
        self.relativePosition = relativePosition
        self.startOffset = startOffset
    }
    
    // Computed property for display in highlights list
    var displayText: String {
        return "\(text)"
    }
    
    // Custom encoding for NSRange since it's not Codable by default
    enum CodingKeys: String, CodingKey {
        case spineIndex, pageNumber, text, range, color, date, textContext, relativePosition, startOffset
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spineIndex, forKey: .spineIndex)
        try container.encode(pageNumber, forKey: .pageNumber)
        try container.encode(text, forKey: .text)
        try container.encode(color, forKey: .color)
        try container.encode(date, forKey: .date)
        try container.encode(textContext, forKey: .textContext)
        try container.encode(relativePosition, forKey: .relativePosition)
        try container.encodeIfPresent(startOffset, forKey: .startOffset)
        
        // Encode NSRange as location and length
        let rangeDict = ["location": range.location, "length": range.length]
        try container.encode(rangeDict, forKey: .range)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spineIndex = try container.decode(Int.self, forKey: .spineIndex)
        pageNumber = try container.decode(Int.self, forKey: .pageNumber)
        text = try container.decode(String.self, forKey: .text)
        color = try container.decode(String.self, forKey: .color)
        date = try container.decode(Date.self, forKey: .date)
        textContext = try container.decodeIfPresent(String.self, forKey: .textContext) ?? ""
        relativePosition = try container.decodeIfPresent(Double.self, forKey: .relativePosition) ?? 0.0
        startOffset = try container.decodeIfPresent(Int.self, forKey: .startOffset)
        
        // Decode NSRange from location and length
        let rangeDict = try container.decode([String: Int].self, forKey: .range)
        let location = rangeDict["location"] ?? 0
        let length = rangeDict["length"] ?? 0
        range = NSRange(location: location, length: length)
    }
}
