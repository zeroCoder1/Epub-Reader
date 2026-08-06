//
//  EPUBParser.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//


import Foundation
import ZipArchive
import SwiftSoup

class EPUBParser {
    static func parseEPUB(at url: URL) -> (metadata: EPUBMetadata, spine: [EPUBSpineItem], toc: [EPUBTOCItem], baseURL: URL)? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try SSZipArchive.unzipFile(atPath: url.path, toDestination: tempDir.path)
            let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
            guard let opfPath = parseContainerXML(at: containerURL) else { return nil }
            let opfURL = tempDir.appendingPathComponent(opfPath)
            guard let (metadata, spine, tocPath, opfDirectoryURL) = parseOPFFile(at: opfURL, rootURL: tempDir) else { return nil }
            let tocURL = URL(fileURLWithPath: tocPath, relativeTo: opfDirectoryURL).standardizedFileURL
            let toc = parseTOCFile(at: tocURL, rootURL: tempDir)
            return (metadata, spine, toc, tempDir)
        } catch {
            print("Error parsing EPUB: \(error)")
            return nil
        }
    }
    
    private static func parseContainerXML(at url: URL) -> String? {
        guard let xmlString = try? String(contentsOf: url),
              let doc = try? SwiftSoup.parse(xmlString) else { return nil }
        do {
            let rootFile = try doc.select("rootfile").first()
            return try rootFile?.attr("full-path")
        } catch {
            print("Error parsing container.xml: \(error)")
            return nil
        }
    }
    
    private static func parseOPFFile(at url: URL, rootURL: URL) -> (EPUBMetadata, [EPUBSpineItem], String, URL)? {
        guard let xmlString = try? String(contentsOf: url),
              let doc = try? SwiftSoup.parse(xmlString) else { return nil }
        
        do {
            let opfDirectoryURL = url.deletingLastPathComponent()

            // Extract metadata by directly targeting tag names
            let metadataElement = try doc.select("metadata").first()
            let title = try metadataElement?.getElementsByTag("dc:title").first()?.text() ?? "Unknown Title"
            let author = try metadataElement?.getElementsByTag("dc:creator").first()?.text() ?? "Unknown Author"

            // Extract spine items
            var spineItems: [EPUBSpineItem] = []
            let manifestItems = try doc.select("manifest item")
            let spineRefs = try doc.select("spine itemref")

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
            let metadata = EPUBMetadata(title: title, author: author, coverImageURL: coverImageURL)
            
            for ref in spineRefs {
                let idref = try ref.attr("idref")
                var matchingItem: Element? = nil
                for item in manifestItems {
                    if (try? item.attr("id")) == idref {
                        matchingItem = item
                        break
                    }
                }
                if let item = matchingItem {
                    let href = try item.attr("href")
                    let fullURL = URL(fileURLWithPath: href, relativeTo: opfDirectoryURL).standardizedFileURL
                    let normalizedHref = relativePath(from: rootURL, to: fullURL)
                    spineItems.append(EPUBSpineItem(id: idref, href: normalizedHref))
                }
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
            
            return (metadata, spineItems, tocPath, opfDirectoryURL)
        } catch {
            print("Error parsing .opf file: \(error)")
            return nil
        }
    }
    
    private static func parseTOCFile(at url: URL, rootURL: URL) -> [EPUBTOCItem] {
        guard let xmlString = try? String(contentsOf: url),
              let doc = try? SwiftSoup.parse(xmlString) else { return [] }
        do {
            var tocItems: [EPUBTOCItem] = []

            // EPUB3 TOC (XHTML nav). A nav document can also hold landmarks and page-list navs,
            // so prefer the <nav epub:type="toc"> and only fall back to the first nav.
            let navs = try doc.select("nav")
            var tocNav: Element? = nil
            for nav in navs.array() where ((try? nav.attr("epub:type")) ?? "").split(separator: " ").contains("toc") {
                tocNav = nav
                break
            }
            if let navContainer = tocNav ?? navs.first() {
                let navLinks = try navContainer.select("a")
                for link in navLinks {
                    let label = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    let href = try link.attr("href")
                    if !label.isEmpty, !href.isEmpty {
                        let normalizedHref = normalizeTOCHref(href, tocURL: url, rootURL: rootURL)
                        tocItems.append(EPUBTOCItem(label: label, href: normalizedHref))
                    }
                }
            }

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
