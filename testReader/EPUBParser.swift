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
            guard let (metadata, spine, tocPath) = parseOPFFile(at: opfURL, baseURL: tempDir) else { return nil }
            let toc = parseTOCFile(at: tempDir.appendingPathComponent("/OPS"), baseURL: tempDir)
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
    
    private static func parseOPFFile(at url: URL, baseURL: URL) -> (EPUBMetadata, [EPUBSpineItem], String)? {
        guard let xmlString = try? String(contentsOf: url),
              let doc = try? SwiftSoup.parse(xmlString) else { return nil }
        
        do {
            // Extract metadata by directly targeting tag names
            let metadataElement = try doc.select("metadata").first()
            let title = try metadataElement?.getElementsByTag("dc:title").first()?.text() ?? "Unknown Title"
            let author = try metadataElement?.getElementsByTag("dc:creator").first()?.text() ?? "Unknown Author"
            let metadata = EPUBMetadata(title: title, author: author)
            
            // Extract spine items
            var spineItems: [EPUBSpineItem] = []
            let manifestItems = try doc.select("manifest item")
            let spineRefs = try doc.select("spine itemref")
            
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
                    spineItems.append(EPUBSpineItem(id: idref, href: href))
                }
            }
            
            // Extract TOC path
            let tocID = try doc.select("spine").attr("toc")
            var tocItem: Element? = nil
            for item in manifestItems {
                if (try? item.attr("id")) == tocID {
                    tocItem = item
                    break
                }
            }
            let tocPath = try tocItem?.attr("href") ?? ""
            
            return (metadata, spineItems, tocPath)
        } catch {
            print("Error parsing .opf file: \(error)")
            return nil
        }
    }
    
    private static func parseTOCFile(at url: URL, baseURL: URL) -> [EPUBTOCItem] {
        guard let xmlString = try? String(contentsOf: url.appending(path: "toc.xhtml")),
              let doc = try? SwiftSoup.parse(xmlString) else { return [] }
        do {
            let navPoints = try doc.select("nav")
            var tocItems: [EPUBTOCItem] = []
            for nav in navPoints {
                let label = try nav.select("navLabel text").first()?.text() ?? ""
                let href = try nav.select("content").attr("src")
                tocItems.append(EPUBTOCItem(label: label, href: href))
            }
            return tocItems
        } catch {
            print("Error parsing TOC: \(error)")
            return []
        }
    }
}
