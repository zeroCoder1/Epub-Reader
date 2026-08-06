//
//  EPUBParser.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//


import Foundation
import ZipArchive
import SwiftSoup

enum EPUBParseError: LocalizedError {
    case archiveTooLarge
    case tooManyEntries

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge:
            return "This EPUB is too large to open safely."
        case .tooManyEntries:
            return "This EPUB contains too many files to open safely."
        }
    }
}

class EPUBParser {
    // Safety caps applied before extraction to guard against zip bombs / inode exhaustion.
    // Generous enough for image-heavy books; tune here if a legitimate book is rejected.
    private static let maxEntryCount = 20_000
    private static let maxTotalUncompressedBytes: UInt64 = 2 * 1024 * 1024 * 1024 // 2 GB
    // Orphaned extractions (e.g. from a crash) older than this are swept on the next open.
    private static let staleExtractionAge: TimeInterval = 60 * 60 // 1 hour

    // All extractions live under one root so orphans can be swept safely.
    private static var extractionsRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("EPUBExtractions", isDirectory: true)
    }

    static func parseEPUB(at url: URL) throws -> (metadata: EPUBMetadata, spine: [EPUBSpineItem], toc: [EPUBTOCItem], baseURL: URL)? {
        sweepStaleExtractions()
        try enforceArchiveLimits(at: url)

        let root = extractionsRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tempDir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)

        guard SSZipArchive.unzipFile(atPath: url.path, toDestination: tempDir.path) else {
            try? FileManager.default.removeItem(at: tempDir)
            print("Error parsing EPUB: unzip failed")
            return nil
        }
        validateMimetype(in: tempDir)
        let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
        guard let opfPath = parseContainerXML(at: containerURL) else {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }
        let opfURL = tempDir.appendingPathComponent(opfPath)
        guard let (metadata, spine, tocPath, guideItems, opfDirectoryURL) = parseOPFFile(at: opfURL, rootURL: tempDir) else {
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }
        let tocURL = URL(fileURLWithPath: tocPath, relativeTo: opfDirectoryURL).standardizedFileURL
        let parsedTOC = parseTOCFile(at: tocURL, rootURL: tempDir)
        // Fall back to the EPUB2 <guide> when neither the nav doc nor the NCX yielded a TOC.
        let toc = parsedTOC.isEmpty ? guideItems : parsedTOC
        return (metadata, spine, toc, tempDir)
    }

    // Removes a book's extracted files; call when the reader closes.
    static func cleanupExtraction(at baseURL: URL) {
        // Only touch directories we created under the extractions root.
        guard baseURL.deletingLastPathComponent().standardizedFileURL == extractionsRoot.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: baseURL)
    }

    // Deletes extraction directories left behind by a previous run (e.g. a crash).
    private static func sweepStaleExtractions() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: extractionsRoot,
                                                          includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(-staleExtractionAge)
        for dir in contents {
            let modified = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: dir)
            }
        }
    }

    // Rejects archives that are too large or hold too many entries, before extracting anything.
    private static func enforceArchiveLimits(at url: URL) throws {
        let payload = SSZipArchive.payloadSizeForArchive(atPath: url.path, error: nil).uint64Value
        if payload > maxTotalUncompressedBytes {
            throw EPUBParseError.archiveTooLarge
        }
        if let entries = zipEntryCount(at: url), entries > maxEntryCount {
            throw EPUBParseError.tooManyEntries
        }
    }

    // Reads the total entry count from the ZIP End-Of-Central-Directory record without
    // extracting. Returns nil when the record can't be located (e.g. ZIP64), in which case
    // the count check is skipped and the total-size cap still applies.
    private static func zipEntryCount(at url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
              fileSize >= 22 else { return nil }
        // EOCD is at most 22 bytes + a 64 KB comment; scan the tail.
        let scanLen = min(fileSize, 22 + 65_536)
        try? handle.seek(toOffset: fileSize - scanLen)
        guard let tail = try? handle.readToEnd(), tail.count >= 22 else { return nil }
        let sig: [UInt8] = [0x50, 0x4b, 0x05, 0x06] // "PK\5\6"
        // Search backwards for the EOCD signature.
        var i = tail.count - 22
        while i >= 0 {
            if Array(tail[i..<i+4]) == sig {
                // Total-entries field is 2 bytes at offset 10, little-endian.
                let lo = Int(tail[i + 10]); let hi = Int(tail[i + 11])
                let count = lo | (hi << 8)
                return count == 0xFFFF ? nil : count // 0xFFFF signals ZIP64; skip the check.
            }
            i -= 1
        }
        return nil
    }

    // Checks the OCF `mimetype` entry. We stay tolerant (a malformed/missing mimetype still
    // proceeds, matching real-world readers), but record a diagnostic instead of failing silently.
    private static func validateMimetype(in root: URL) {
        let mimetypeURL = root.appendingPathComponent("mimetype")
        guard let contents = try? String(contentsOf: mimetypeURL, encoding: .utf8) else {
            print("EPUB diagnostic: missing mimetype entry — proceeding anyway.")
            return
        }
        if contents.trimmingCharacters(in: .whitespacesAndNewlines) != "application/epub+zip" {
            print("EPUB diagnostic: unexpected mimetype contents — proceeding anyway.")
        }
    }

    // Media types WebKit can render directly as a spine document.
    private static let renderableMediaTypes: Set<String> = [
        "application/xhtml+xml", "text/html", "image/svg+xml"
    ]

    // Returns the id of the first renderable resource for a spine item, following the
    // manifest `fallback` chain when the primary media type isn't renderable. Returns nil
    // if the chain has no renderable resource (caller then keeps the original href).
    private static func resolveRenderableID(_ id: String,
                                            in manifest: [String: (href: String, mediaType: String, fallback: String?)]) -> String? {
        var currentID: String? = id
        var visited = Set<String>()
        while let cid = currentID, !visited.contains(cid), let entry = manifest[cid] {
            if renderableMediaTypes.contains(entry.mediaType.lowercased()) { return cid }
            visited.insert(cid)
            currentID = entry.fallback
        }
        return nil
    }

    private static func parseContainerXML(at url: URL) -> String? {
        guard let xmlString = try? String(contentsOf: url),
              let doc = try? SwiftSoup.parse(xmlString, "", Parser.xmlParser()) else { return nil }
        do {
            // A container may list several rootfiles (multiple renditions). Prefer the first
            // one declared as an OPF package; fall back to the first rootfile of any type.
            let rootFiles = try doc.select("rootfile").array()
            for rf in rootFiles where ((try? rf.attr("media-type")) ?? "") == "application/oebps-package+xml" {
                let path = (try? rf.attr("full-path")) ?? ""
                if !path.isEmpty { return path }
            }
            return try rootFiles.first?.attr("full-path")
        } catch {
            print("Error parsing container.xml: \(error)")
            return nil
        }
    }
    
    private static func parseOPFFile(at url: URL, rootURL: URL) -> (EPUBMetadata, [EPUBSpineItem], String, [EPUBTOCItem], URL)? {
        // The OPF is XML; the HTML tree-builder can silently nest self-closing
        // <item/>/<itemref/> entries (common from InDesign/Sigil), so parse in XML mode.
        guard let xmlString = try? String(contentsOf: url),
              let doc = try? SwiftSoup.parse(xmlString, "", Parser.xmlParser()) else { return nil }
        
        do {
            let opfDirectoryURL = url.deletingLastPathComponent()

            // Extract metadata by directly targeting tag names
            let metadataElement = try doc.select("metadata").first()
            func dcValue(_ tag: String) -> String? {
                let value = try? metadataElement?.getElementsByTag(tag).first()?
                    .text().trimmingCharacters(in: .whitespacesAndNewlines)
                let unwrapped = value ?? nil
                return (unwrapped?.isEmpty == false) ? unwrapped : nil
            }
            let title = dcValue("dc:title") ?? "Unknown Title"
            let author = dcValue("dc:creator") ?? "Unknown Author"
            let identifier = dcValue("dc:identifier")
            let language = dcValue("dc:language")
            let publisher = dcValue("dc:publisher")
            let bookDescription = dcValue("dc:description")
            let publicationDate = dcValue("dc:date")

            // Book-level fixed-layout default: EPUB3 rendition:layout, or the legacy
            // fixed-layout meta. Individual spine items can still override this below.
            var bookIsFixedLayout = false
            var renditionSpread: String? = nil
            for meta in (try? metadataElement?.select("meta").array()) ?? [] {
                if (try? meta.attr("property")) == "rendition:layout",
                   ((try? meta.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "pre-paginated" {
                    bookIsFixedLayout = true
                }
                if (try? meta.attr("name")) == "fixed-layout",
                   ((try? meta.attr("content")) ?? "").lowercased() == "true" {
                    bookIsFixedLayout = true
                }
                if (try? meta.attr("property")) == "rendition:spread" {
                    let value = ((try? meta.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !value.isEmpty { renditionSpread = value }
                }
            }

            // Extract spine items
            var spineItems: [EPUBSpineItem] = []
            let manifestItems = try doc.select("manifest item")
            let spineRefs = try doc.select("spine itemref")

            // Manifest lookup by id for fallback resolution: id -> (href, media-type, fallback id).
            var manifestByID: [String: (href: String, mediaType: String, fallback: String?)] = [:]
            for item in manifestItems {
                guard let id = try? item.attr("id"), !id.isEmpty else { continue }
                let href = (try? item.attr("href")) ?? ""
                let mediaType = (try? item.attr("media-type")) ?? ""
                let fallback = (try? item.attr("fallback")).flatMap { $0.isEmpty ? nil : $0 }
                manifestByID[id] = (href, mediaType, fallback)
            }

            // Resolve cover image (EPUB3 properties, then EPUB2 meta name=cover)
            var coverImageURL: URL? = nil
            for item in manifestItems where ((try? item.attr("properties")) ?? "").contains("cover-image") {
                let href = try item.attr("href")
                coverImageURL = URL(fileURLWithPath: href, relativeTo: opfDirectoryURL).standardizedFileURL
                break
            }
            if coverImageURL == nil,
               let coverId = try? doc.select("metadata meta[name=cover]").first()?.attr("content"),
               !coverId.isEmpty {
                for item in manifestItems where (try? item.attr("id")) == coverId {
                    let href = try item.attr("href")
                    coverImageURL = URL(fileURLWithPath: href, relativeTo: opfDirectoryURL).standardizedFileURL
                    break
                }
            }
            let metadata = EPUBMetadata(title: title, author: author, coverImageURL: coverImageURL,
                                        identifier: identifier, language: language, publisher: publisher,
                                        bookDescription: bookDescription, publicationDate: publicationDate,
                                        renditionSpread: renditionSpread)

            for ref in spineRefs {
                let idref = try ref.attr("idref")
                guard manifestByID[idref] != nil else { continue }
                // If the primary resource isn't a WebKit-renderable document, walk the manifest
                // fallback chain to the first renderable resource.
                let resolvedID = resolveRenderableID(idref, in: manifestByID) ?? idref
                let href = manifestByID[resolvedID]?.href ?? ""
                guard !href.isEmpty else { continue }
                let fullURL = URL(fileURLWithPath: href, relativeTo: opfDirectoryURL).standardizedFileURL
                let normalizedHref = relativePath(from: rootURL, to: fullURL)

                // linear defaults to "yes"; only an explicit linear="no" marks non-linear content.
                let linearAttr = ((try? ref.attr("linear")) ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                let isLinear = linearAttr != "no"

                // Per-itemref rendition:layout override, else the book-level default.
                let props = (try? ref.attr("properties")) ?? ""
                let isFixed: Bool
                if props.contains("rendition:layout-pre-paginated") { isFixed = true }
                else if props.contains("rendition:layout-reflowable") { isFixed = false }
                else { isFixed = bookIsFixedLayout }

                // Page position within a spread (property may be namespaced or bare).
                let pageSpread: PageSpread
                if props.contains("page-spread-left") { pageSpread = .left }
                else if props.contains("page-spread-right") { pageSpread = .right }
                else if props.contains("page-spread-center") || props.contains("rendition:page-spread-center") { pageSpread = .center }
                else { pageSpread = .auto }

                spineItems.append(EPUBSpineItem(id: idref, href: normalizedHref, linear: isLinear,
                                                isFixedLayout: isFixed, pageSpread: pageSpread))
            }
            
            // Extract TOC path. EPUB3 declares the nav document via a manifest item with
            // properties="nav"; EPUB2 points spine[toc] at an NCX. Prefer the EPUB3 nav, then
            // fall back to the NCX so pure-EPUB3 books (no spine[toc]) still get a TOC.
            var tocItem: Element? = nil
            for item in manifestItems where ((try? item.attr("properties")) ?? "").split(separator: " ").contains("nav") {
                tocItem = item
                break
            }
            if tocItem == nil {
                let tocID = try doc.select("spine").attr("toc")
                if !tocID.isEmpty {
                    for item in manifestItems where (try? item.attr("id")) == tocID {
                        tocItem = item
                        break
                    }
                }
            }
            let tocPath = try tocItem?.attr("href") ?? ""

            // EPUB2 <guide> references — used as a TOC fallback when no nav/NCX TOC exists.
            var guideItems: [EPUBTOCItem] = []
            for ref in (try? doc.select("guide reference").array()) ?? [] {
                let href = (try? ref.attr("href")) ?? ""
                let title = ((try? ref.attr("title")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let type = (try? ref.attr("type")) ?? ""
                let label = !title.isEmpty ? title : type
                if !href.isEmpty, !label.isEmpty {
                    guideItems.append(EPUBTOCItem(label: label, href: normalizeTOCHref(href, tocURL: url, rootURL: rootURL)))
                }
            }

            return (metadata, spineItems, tocPath, guideItems, opfDirectoryURL)
        } catch {
            print("Error parsing .opf file: \(error)")
            return nil
        }
    }
    
    private static func parseTOCFile(at url: URL, rootURL: URL) -> [EPUBTOCItem] {
        // An EPUB2 NCX is XML (self-closing <content src=".../>), so parse it in XML mode;
        // an EPUB3 nav document is XHTML and is fine on the default HTML parser.
        let isNCX = url.pathExtension.lowercased() == "ncx"
        guard let xmlString = try? String(contentsOf: url),
              let doc = try? (isNCX ? SwiftSoup.parse(xmlString, "", Parser.xmlParser())
                                    : SwiftSoup.parse(xmlString)) else { return [] }
        do {
            var tocItems: [EPUBTOCItem] = []

            // EPUB3 nav document — may hold several <nav>s (toc, landmarks, page-list).
            let navs = try doc.select("nav").array()
            func navType(_ nav: Element) -> [Substring] {
                return ((try? nav.attr("epub:type")) ?? "").split(separator: " ")
            }
            func extractLinks(from nav: Element, into items: inout [EPUBTOCItem]) {
                guard let links = try? nav.select("a") else { return }
                for link in links {
                    let label = (try? link.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
                    let href = (try? link.attr("href")) ?? ""
                    if !label.isEmpty, !href.isEmpty {
                        items.append(EPUBTOCItem(label: label, href: normalizeTOCHref(href, tocURL: url, rootURL: rootURL)))
                    }
                }
            }
            // Prefer the explicit toc nav; otherwise the first nav that isn't landmarks/page-list
            // (an untyped single nav is the TOC).
            let tocNav = navs.first(where: { navType($0).contains("toc") })
                ?? navs.first(where: { let t = navType($0); return !t.contains("landmarks") && !t.contains("page-list") })
            if let tocNav { extractLinks(from: tocNav, into: &tocItems) }

            // EPUB2 TOC (NCX navPoint)
            if tocItems.isEmpty {
                let navPoints = try doc.select("navPoint")
                for navPoint in navPoints {
                    let label = try navPoint.select("navLabel text").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let src = try navPoint.select("content").first()?.attr("src") ?? ""
                    if !label.isEmpty, !src.isEmpty {
                        let normalizedHref = normalizeTOCHref(src, tocURL: url, rootURL: rootURL)
                        tocItems.append(EPUBTOCItem(label: label, href: normalizedHref))
                    }
                }
            }

            // Last resort: the landmarks nav (cover/toc/bodymatter) is better than an empty TOC.
            if tocItems.isEmpty, let landmarks = navs.first(where: { navType($0).contains("landmarks") }) {
                extractLinks(from: landmarks, into: &tocItems)
            }

            return tocItems
        } catch {
            print("Error parsing TOC: \(error)")
            return []
        }
    }

    private static func normalizeTOCHref(_ href: String, tocURL: URL, rootURL: URL) -> String {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(parts.first ?? "")
        let fragmentPart = parts.count > 1 ? String(parts[1]) : nil

        let normalizedPath: String
        if pathPart.isEmpty {
            normalizedPath = relativePath(from: rootURL, to: tocURL)
        } else {
            let absolute = URL(fileURLWithPath: pathPart, relativeTo: tocURL.deletingLastPathComponent()).standardizedFileURL
            normalizedPath = relativePath(from: rootURL, to: absolute)
        }

        if let fragmentPart, !fragmentPart.isEmpty {
            return "\(normalizedPath)#\(fragmentPart)"
        }
        return normalizedPath
    }

    private static func relativePath(from baseURL: URL, to targetURL: URL) -> String {
        let basePath = baseURL.standardizedFileURL.path
        let targetPath = targetURL.standardizedFileURL.path
        if targetPath.hasPrefix(basePath + "/") {
            return String(targetPath.dropFirst(basePath.count + 1))
        }
        return targetURL.lastPathComponent
    }
}
