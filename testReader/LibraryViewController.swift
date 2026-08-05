//
//  LibraryViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//


import UIKit

class LibraryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView()
    private var epubFiles: [URL] = []
    private let fileManager = FileManager.default
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "EPUB Library"
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupTableView()
        loadEpubFiles()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadEpubFiles()
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "",
            style: .plain, 
            target: self, 
            action: nil
        )
    }
 
    
    private func setupTableView() {
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .systemBackground
        tableView.separatorColor = .separator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EpubCell")
    }
    
    private func loadEpubFiles() {
        let bundledEPUBs = discoverEPUBsInBundle()
        let documentEPUBs = discoverEPUBsInDocumentsDirectory()

        // Keep one entry per absolute path and sort by display name.
        var uniqueByPath: [String: URL] = [:]
        for url in bundledEPUBs + documentEPUBs {
            uniqueByPath[url.standardizedFileURL.path] = url
        }

        epubFiles = uniqueByPath.values.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        tableView.reloadData()
    }

    private func discoverEPUBsInBundle() -> [URL] {
        guard let bundleRootURL = Bundle.main.resourceURL else {
            return []
        }
        return discoverEPUBsRecursively(at: bundleRootURL)
    }

    private func discoverEPUBsInDocumentsDirectory() -> [URL] {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        return discoverEPUBsRecursively(at: documentsURL)
    }

    private func discoverEPUBsRecursively(at rootURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return []
        }

        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "epub" {
                result.append(fileURL)
            }
        }
        return result
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return epubFiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EpubCell", for: indexPath)
        let fileURL = epubFiles[indexPath.row]
        let isBundledFile = fileURL.standardizedFileURL.path.hasPrefix((Bundle.main.resourceURL?.standardizedFileURL.path ?? "") + "/")
        cell.textLabel?.text = isBundledFile ? "\(fileURL.lastPathComponent) (Bundled)" : fileURL.lastPathComponent
        cell.textLabel?.textColor = .label
        cell.backgroundColor = .systemBackground
        cell.contentView.backgroundColor = .systemBackground
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedURL = epubFiles[indexPath.row]

        do {
            let readableURL = try prepareEPUBForReading(from: selectedURL)
            let readerVC = ReaderViewController(epubURL: readableURL)
            navigationController?.pushViewController(readerVC, animated: true)
        } catch {
            showLoadError(message: error.localizedDescription)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func prepareEPUBForReading(from sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL else {
            throw NSError(domain: "EPUBReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Selected EPUB path is invalid."])
        }

        let bundlePath = (Bundle.main.resourceURL?.standardizedFileURL.path ?? "") + "/"
        let sourcePath = sourceURL.standardizedFileURL.path

        // EPUBs inside the app bundle are read-only; copy them to caches for stable access.
        if sourcePath.hasPrefix(bundlePath) {
            let cachesURL = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let targetDirectory = cachesURL.appendingPathComponent("BundledEPUBs", isDirectory: true)
            try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

            let targetURL = targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.copyItem(at: sourceURL, to: targetURL)
            return targetURL
        }

        return sourceURL
    }

    private func showLoadError(message: String) {
        let alert = UIAlertController(title: "Unable to Open EPUB", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
