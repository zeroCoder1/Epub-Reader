//
//  SettingsViewController.swift
//  testReader
//
//  Created by shrutesh sharma on 11/03/25.
//

import UIKit

class SettingsViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    private let darkModeSwitch = UISwitch()
    private let backgroundColorPicker = UIPickerView()
    private let fontFamilyPicker = UIPickerView()
    private let fontSizeSlider = UISlider()
    private let highlightColorPicker = UIPickerView()
    private let pageCurlSwitch = UISwitch()
    
    private let colors = ["#FFFFFF", "#F5F5DC", "#E0E0E0"]
    private let colorNames = ["White", "Beige", "Gray"]
    private let fonts = ["Georgia", "Times New Roman", "Helvetica"]
    private let highlightColors = ["yellow", "green", "pink"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = .white
        setupUI()
        loadCurrentSettings()
    }
    
    private func setupUI() {
        let darkModeLabel = UILabel()
        darkModeLabel.text = "Dark Mode"
        darkModeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(darkModeLabel)
        darkModeSwitch.translatesAutoresizingMaskIntoConstraints = false
        darkModeSwitch.addTarget(self, action: #selector(saveSettings), for: .valueChanged)
        view.addSubview(darkModeSwitch)
        
        let bgLabel = UILabel()
        bgLabel.text = "Background Color"
        bgLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bgLabel)
        backgroundColorPicker.translatesAutoresizingMaskIntoConstraints = false
        backgroundColorPicker.dataSource = self
        backgroundColorPicker.delegate = self
        view.addSubview(backgroundColorPicker)
        
        let fontLabel = UILabel()
        fontLabel.text = "Font Family"
        fontLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fontLabel)
        fontFamilyPicker.translatesAutoresizingMaskIntoConstraints = false
        fontFamilyPicker.dataSource = self
        fontFamilyPicker.delegate = self
        view.addSubview(fontFamilyPicker)
        
        let sizeLabel = UILabel()
        sizeLabel.text = "Font Size"
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sizeLabel)
        fontSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        fontSizeSlider.minimumValue = 12
        fontSizeSlider.maximumValue = 24
        fontSizeSlider.addTarget(self, action: #selector(saveSettings), for: .valueChanged)
        view.addSubview(fontSizeSlider)
        
        let highlightLabel = UILabel()
        highlightLabel.text = "Highlight Color"
        highlightLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(highlightLabel)
        highlightColorPicker.translatesAutoresizingMaskIntoConstraints = false
        highlightColorPicker.dataSource = self
        highlightColorPicker.delegate = self
        view.addSubview(highlightColorPicker)
        
        let pageCurlLabel = UILabel()
        pageCurlLabel.text = "Page Curl Animation"
        pageCurlLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageCurlLabel)
        pageCurlSwitch.translatesAutoresizingMaskIntoConstraints = false
        pageCurlSwitch.addTarget(self, action: #selector(saveSettings), for: .valueChanged)
        view.addSubview(pageCurlSwitch)
        
        NSLayoutConstraint.activate([
            darkModeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            darkModeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            darkModeSwitch.centerYAnchor.constraint(equalTo: darkModeLabel.centerYAnchor),
            darkModeSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            bgLabel.topAnchor.constraint(equalTo: darkModeLabel.bottomAnchor, constant: 20),
            bgLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            backgroundColorPicker.topAnchor.constraint(equalTo: bgLabel.bottomAnchor, constant: 10),
            backgroundColorPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundColorPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundColorPicker.heightAnchor.constraint(equalToConstant: 100),
            
            fontLabel.topAnchor.constraint(equalTo: backgroundColorPicker.bottomAnchor, constant: 20),
            fontLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            fontFamilyPicker.topAnchor.constraint(equalTo: fontLabel.bottomAnchor, constant: 10),
            fontFamilyPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fontFamilyPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fontFamilyPicker.heightAnchor.constraint(equalToConstant: 100),
            
            sizeLabel.topAnchor.constraint(equalTo: fontFamilyPicker.bottomAnchor, constant: 20),
            sizeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            fontSizeSlider.centerYAnchor.constraint(equalTo: sizeLabel.centerYAnchor),
            fontSizeSlider.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 20),
            fontSizeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            highlightLabel.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 20),
            highlightLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            highlightColorPicker.topAnchor.constraint(equalTo: highlightLabel.bottomAnchor, constant: 10),
            highlightColorPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            highlightColorPicker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            highlightColorPicker.heightAnchor.constraint(equalToConstant: 100),
            
            pageCurlLabel.topAnchor.constraint(equalTo: highlightColorPicker.bottomAnchor, constant: 20),
            pageCurlLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            pageCurlSwitch.centerYAnchor.constraint(equalTo: pageCurlLabel.centerYAnchor),
            pageCurlSwitch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }
    
    private func loadCurrentSettings() {
        darkModeSwitch.isOn = UserDefaults.standard.bool(forKey: "isDarkMode")
        if let bgColor = UserDefaults.standard.string(forKey: "backgroundColor"),
           let index = colors.firstIndex(of: bgColor) {
            backgroundColorPicker.selectRow(index, inComponent: 0, animated: false)
        }
        if let font = UserDefaults.standard.string(forKey: "fontFamily"),
           let index = fonts.firstIndex(of: font) {
            fontFamilyPicker.selectRow(index, inComponent: 0, animated: false)
        }
        fontSizeSlider.value = Float(UserDefaults.standard.integer(forKey: "fontSize") > 0 ? UserDefaults.standard.integer(forKey: "fontSize") : 16)
        if let highlightColor = UserDefaults.standard.string(forKey: "highlightColor"),
           let index = highlightColors.firstIndex(of: highlightColor) {
            highlightColorPicker.selectRow(index, inComponent: 0, animated: false)
        }
        pageCurlSwitch.isOn = UserDefaults.standard.bool(forKey: "isPageCurlEnabled")
    }
    
    @objc private func saveSettings() {
        UserDefaults.standard.set(darkModeSwitch.isOn, forKey: "isDarkMode")
        let bgIndex = backgroundColorPicker.selectedRow(inComponent: 0)
        UserDefaults.standard.set(colors[bgIndex], forKey: "backgroundColor")
        let fontIndex = fontFamilyPicker.selectedRow(inComponent: 0)
        UserDefaults.standard.set(fonts[fontIndex], forKey: "fontFamily")
        UserDefaults.standard.set(Int(fontSizeSlider.value), forKey: "fontSize")
        let highlightIndex = highlightColorPicker.selectedRow(inComponent: 0)
        UserDefaults.standard.set(highlightColors[highlightIndex], forKey: "highlightColor")
        UserDefaults.standard.set(pageCurlSwitch.isOn, forKey: "isPageCurlEnabled")
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView == backgroundColorPicker { return colors.count }
        if pickerView == fontFamilyPicker { return fonts.count }
        if pickerView == highlightColorPicker { return highlightColors.count }
        return 0
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView == backgroundColorPicker { return colorNames[row] }
        if pickerView == fontFamilyPicker { return fonts[row] }
        if pickerView == highlightColorPicker { return highlightColors[row] }
        return nil
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        saveSettings()
    }
}
