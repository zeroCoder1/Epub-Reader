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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "EPUB Library"
        view.backgroundColor = .white
        setupNavigationBar()
        setupTableView()
        loadEpubFiles()
    }
    
    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Settings", 
            style: .plain, 
            target: self, 
            action: #selector(openSettings)
        )
    }
    
    @objc private func openSettings() {
        let settingsVC = SettingsViewController()
        navigationController?.pushViewController(settingsVC, animated: true)
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EpubCell")
    }
    
    private func loadEpubFiles() {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
            epubFiles = files.filter { $0.pathExtension.lowercased() == "epub" }
            tableView.reloadData()
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return epubFiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "EpubCell", for: indexPath)
        cell.textLabel?.text = epubFiles[indexPath.row].lastPathComponent
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let readerVC = ReaderViewController(epubURL: epubFiles[indexPath.row])
        navigationController?.pushViewController(readerVC, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
