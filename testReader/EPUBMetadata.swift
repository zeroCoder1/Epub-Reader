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
}

struct EPUBSpineItem {
    let id: String
    let href: String
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
    
    init(spineIndex: Int, pageNumber: Int, text: String, range: NSRange, color: String, textContext: String = "", relativePosition: Double = 0.0) {
        self.spineIndex = spineIndex
        self.pageNumber = pageNumber
        self.text = text
        self.range = range
        self.color = color
        self.date = Date()
        self.textContext = textContext
        self.relativePosition = relativePosition
    }
    
    // Computed property for display in highlights list
    var displayText: String {
        return "\(text)"
    }
    
    // Custom encoding for NSRange since it's not Codable by default
    enum CodingKeys: String, CodingKey {
        case spineIndex, pageNumber, text, range, color, date, textContext, relativePosition
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
        
        // Decode NSRange from location and length
        let rangeDict = try container.decode([String: Int].self, forKey: .range)
        let location = rangeDict["location"] ?? 0
        let length = rangeDict["length"] ?? 0
        range = NSRange(location: location, length: length)
    }
}
