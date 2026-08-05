//
//  CustomizeThemeViewController.swift
//  testReader
//

import UIKit

protocol CustomizeThemeViewControllerDelegate: AnyObject {
    func customizeThemeDidUpdate(_ controller: CustomizeThemeViewController)
}

final class CustomizeThemeViewController: UIViewController {
    weak var delegate: CustomizeThemeViewControllerDelegate?

    // Friendly name -> CSS font-family
    private let fonts: [(name: String, css: String)] = [
        ("Charter", "Charter"),
        ("Georgia", "Georgia"),
        ("Times New Roman", "Times New Roman"),
        ("Palatino", "Palatino"),
        ("Helvetica", "Helvetica"),
        ("System", "-apple-system")
    ]

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let previewTitle = UILabel()
    private let previewBody = UILabel()
    private var previewBodyLeading: NSLayoutConstraint!
    private var previewBodyTrailing: NSLayoutConstraint!
    private var previewTitleLeading: NSLayoutConstraint!

    private let fontValueLabel = UILabel()
    private let boldSwitch = UISwitch()
    private let customizeSwitch = UISwitch()
    private let justifySwitch = UISwitch()

    private let lineSpacingSlider = UISlider()
    private let charSpacingSlider = UISlider()
    private let wordSpacingSlider = UISlider()
    private let marginsSlider = UISlider()

    private let lineSpacingValue = UILabel()
    private let charSpacingValue = UILabel()
    private let wordSpacingValue = UILabel()
    private let marginsValue = UILabel()

    private var layoutRowsToDim: [UIView] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        buildHeaderBar()
        buildScroll()
        loadState()
        updatePreview()
        updateDimming()
    }

    // MARK: - Header bar

    private func buildHeaderBar() {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = .secondarySystemGroupedBackground
        closeButton.layer.cornerRadius = 22
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = UIButton(type: .system)
        doneButton.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
        doneButton.tintColor = .systemBackground
        doneButton.backgroundColor = .label
        doneButton.layer.cornerRadius = 22
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Customize Theme"
        title.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        title.textColor = .label
        title.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(closeButton)
        bar.addSubview(title)
        bar.addSubview(doneButton)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 60),

            closeButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            closeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            title.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            doneButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            doneButton.widthAnchor.constraint(equalToConstant: 44),
            doneButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        headerBarBottom = bar.bottomAnchor
    }

    private var headerBarBottom: NSLayoutYAxisAnchor!

    // MARK: - Scroll content

    private func buildScroll() {
        let preview = buildPreview()
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: headerBarBottom),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: preview.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -30),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])

        contentStack.addArrangedSubview(sectionHeader("Text"))
        contentStack.addArrangedSubview(buildTextGroup())
        contentStack.addArrangedSubview(sectionHeader("Accessibility & Layout Options"))
        contentStack.addArrangedSubview(buildLayoutGroup())
        contentStack.addArrangedSubview(buildJustifyGroup())
        contentStack.addArrangedSubview(buildResetButton())
    }

    private func buildPreview() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground

        previewTitle.text = "Aa"
        previewTitle.font = UIFont(name: "Georgia", size: 44) ?? UIFont.systemFont(ofSize: 44)
        previewTitle.textColor = .label
        previewTitle.translatesAutoresizingMaskIntoConstraints = false

        previewBody.numberOfLines = 4
        previewBody.textColor = .label
        previewBody.text = "He did not find out until the wedding that she was simple. Her father had been scrupulous about keeping her veiled until the ceremony, and my father had humored him."
        previewBody.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(previewTitle)
        card.addSubview(previewBody)
        card.translatesAutoresizingMaskIntoConstraints = false
        previewTitleLeading = previewTitle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20)
        previewBodyLeading = previewBody.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20)
        previewBodyTrailing = previewBody.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        NSLayoutConstraint.activate([
            previewTitle.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            previewTitleLeading,
            previewBody.topAnchor.constraint(equalTo: previewTitle.bottomAnchor, constant: 16),
            previewBodyLeading,
            previewBodyTrailing,
            previewBody.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
        return card
    }

    private func sectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        label.textColor = .label
        return label
    }

    private func groupContainer() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.backgroundColor = .secondarySystemGroupedBackground
        stack.layer.cornerRadius = 16
        stack.clipsToBounds = true
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        return stack
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let wrap = UIView()
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
            line.topAnchor.constraint(equalTo: wrap.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor)
        ])
        return wrap
    }

    private func buildTextGroup() -> UIView {
        let group = groupContainer()

        // Font row
        let fontRow = UIControl()
        fontRow.addTarget(self, action: #selector(fontRowTapped), for: .touchUpInside)
        fontRow.translatesAutoresizingMaskIntoConstraints = false
        fontRow.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let fontGlyph = UILabel()
        fontGlyph.text = "Aa"
        fontGlyph.font = UIFont(name: "Georgia", size: 20) ?? UIFont.systemFont(ofSize: 20)
        fontGlyph.textColor = .label

        let fontLabel = UILabel()
        fontLabel.text = "Font"
        fontLabel.font = UIFont.systemFont(ofSize: 18)
        fontLabel.textColor = .label

        fontValueLabel.font = UIFont.systemFont(ofSize: 18)
        fontValueLabel.textColor = .secondaryLabel
        fontValueLabel.textAlignment = .right

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        [fontGlyph, fontLabel, fontValueLabel, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.isUserInteractionEnabled = false
            fontRow.addSubview($0)
        }
        NSLayoutConstraint.activate([
            fontGlyph.leadingAnchor.constraint(equalTo: fontRow.leadingAnchor, constant: 20),
            fontGlyph.centerYAnchor.constraint(equalTo: fontRow.centerYAnchor),
            fontLabel.leadingAnchor.constraint(equalTo: fontGlyph.trailingAnchor, constant: 16),
            fontLabel.centerYAnchor.constraint(equalTo: fontRow.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: fontRow.trailingAnchor, constant: -20),
            chevron.centerYAnchor.constraint(equalTo: fontRow.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            fontValueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            fontValueLabel.centerYAnchor.constraint(equalTo: fontRow.centerYAnchor)
        ])

        // Bold row
        let boldRow = UIView()
        boldRow.translatesAutoresizingMaskIntoConstraints = false
        boldRow.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let boldGlyph = UILabel()
        boldGlyph.text = "B"
        boldGlyph.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        boldGlyph.textColor = .label

        let boldLabel = UILabel()
        boldLabel.text = "Bold Text"
        boldLabel.font = UIFont.systemFont(ofSize: 18)
        boldLabel.textColor = .label

        boldSwitch.addTarget(self, action: #selector(boldChanged), for: .valueChanged)

        [boldGlyph, boldLabel, boldSwitch].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            boldRow.addSubview($0)
        }
        NSLayoutConstraint.activate([
            boldGlyph.leadingAnchor.constraint(equalTo: boldRow.leadingAnchor, constant: 22),
            boldGlyph.centerYAnchor.constraint(equalTo: boldRow.centerYAnchor),
            boldLabel.leadingAnchor.constraint(equalTo: boldGlyph.trailingAnchor, constant: 18),
            boldLabel.centerYAnchor.constraint(equalTo: boldRow.centerYAnchor),
            boldSwitch.trailingAnchor.constraint(equalTo: boldRow.trailingAnchor, constant: -20),
            boldSwitch.centerYAnchor.constraint(equalTo: boldRow.centerYAnchor)
        ])

        group.addArrangedSubview(fontRow)
        group.addArrangedSubview(divider())
        group.addArrangedSubview(boldRow)
        return group
    }

    private func buildLayoutGroup() -> UIView {
        let group = groupContainer()

        // Customize master toggle
        let toggleRow = UIView()
        toggleRow.translatesAutoresizingMaskIntoConstraints = false
        toggleRow.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let toggleLabel = UILabel()
        toggleLabel.text = "Customize"
        toggleLabel.font = UIFont.systemFont(ofSize: 18)
        toggleLabel.textColor = .label

        customizeSwitch.onTintColor = UIColor.systemGreen
        customizeSwitch.addTarget(self, action: #selector(customizeToggleChanged), for: .valueChanged)

        [toggleLabel, customizeSwitch].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            toggleRow.addSubview($0)
        }
        NSLayoutConstraint.activate([
            toggleLabel.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor, constant: 20),
            toggleLabel.centerYAnchor.constraint(equalTo: toggleRow.centerYAnchor),
            customizeSwitch.trailingAnchor.constraint(equalTo: toggleRow.trailingAnchor, constant: -20),
            customizeSwitch.centerYAnchor.constraint(equalTo: toggleRow.centerYAnchor)
        ])

        group.addArrangedSubview(toggleRow)
        group.addArrangedSubview(divider())

        let lineRow = sliderRow(title: "LINE SPACING", icon: "line.3.horizontal", slider: lineSpacingSlider, valueLabel: lineSpacingValue, action: #selector(lineSpacingChanged))
        lineSpacingSlider.minimumValue = 1.0
        lineSpacingSlider.maximumValue = 2.5

        let charRow = sliderRow(title: "CHARACTER SPACING", icon: "textformat.abc", slider: charSpacingSlider, valueLabel: charSpacingValue, action: #selector(charSpacingChanged))
        charSpacingSlider.minimumValue = -10
        charSpacingSlider.maximumValue = 10

        let wordRow = sliderRow(title: "WORD SPACING", icon: "text.justify.left", slider: wordSpacingSlider, valueLabel: wordSpacingValue, action: #selector(wordSpacingChanged))
        wordSpacingSlider.minimumValue = -20
        wordSpacingSlider.maximumValue = 20

        let marginRow = sliderRow(title: "MARGINS", icon: "rectangle.portrait", slider: marginsSlider, valueLabel: marginsValue, action: #selector(marginsChanged))
        marginsSlider.minimumValue = -10
        marginsSlider.maximumValue = 10

        group.addArrangedSubview(lineRow)
        group.addArrangedSubview(divider())
        group.addArrangedSubview(charRow)
        group.addArrangedSubview(divider())
        group.addArrangedSubview(wordRow)
        group.addArrangedSubview(divider())
        group.addArrangedSubview(marginRow)

        layoutRowsToDim = [lineRow, charRow, wordRow, marginRow]
        return group
    }

    private func sliderRow(title: String, icon: String, slider: UISlider, valueLabel: UILabel, action: Selector) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        slider.minimumTrackTintColor = .label
        slider.addTarget(self, action: action, for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = UIFont.systemFont(ofSize: 16)
        valueLabel.textColor = .secondaryLabel
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, iconView, slider, valueLabel].forEach { row.addSubview($0) }
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),

            iconView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            iconView.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -16),

            slider.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),

            valueLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
            valueLabel.widthAnchor.constraint(equalToConstant: 48)
        ])
        return row
    }

    private func buildJustifyGroup() -> UIView {
        let group = groupContainer()
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let label = UILabel()
        label.text = "Justify Text"
        label.font = UIFont.systemFont(ofSize: 18)
        label.textColor = .label

        justifySwitch.addTarget(self, action: #selector(justifyChanged), for: .valueChanged)

        [label, justifySwitch].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            justifySwitch.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -20),
            justifySwitch.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        group.addArrangedSubview(row)
        return group
    }

    private func buildResetButton() -> UIView {
        let group = groupContainer()
        let button = UIButton(type: .system)
        button.setTitle("Reset Theme", for: .normal)
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18)
        button.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 54).isActive = true
        group.addArrangedSubview(button)
        return group
    }

    // MARK: - State

    private func loadState() {
        let d = UserDefaults.standard
        let css = d.string(forKey: "fontFamily") ?? "Georgia"
        fontValueLabel.text = fonts.first(where: { $0.css == css })?.name ?? css
        boldSwitch.isOn = (d.string(forKey: "fontWeight") ?? "normal") == "bold"
        customizeSwitch.isOn = d.object(forKey: "customizeLayoutEnabled") != nil ? d.bool(forKey: "customizeLayoutEnabled") : true
        justifySwitch.isOn = d.bool(forKey: "justifyText")

        lineSpacingSlider.value = d.object(forKey: "lineHeight") != nil ? Float(d.double(forKey: "lineHeight")) : 1.6
        charSpacingSlider.value = Float(d.double(forKey: "letterSpacing"))
        wordSpacingSlider.value = Float(d.double(forKey: "wordSpacing"))
        marginsSlider.value = Float(d.double(forKey: "readerMargins"))
        refreshValueLabels()
    }

    private func refreshValueLabels() {
        lineSpacingValue.text = String(format: "%.2f", lineSpacingSlider.value)
        charSpacingValue.text = "\(Int(charSpacingSlider.value.rounded()))%"
        wordSpacingValue.text = "\(Int(wordSpacingSlider.value.rounded()))%"
        marginsValue.text = "\(Int(marginsSlider.value.rounded()))%"
    }

    private func updateDimming() {
        let enabled = customizeSwitch.isOn
        for row in layoutRowsToDim {
            row.alpha = enabled ? 1.0 : 0.4
            row.isUserInteractionEnabled = enabled
        }
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(boldSwitch.isOn ? "bold" : "normal", forKey: "fontWeight")
        d.set(justifySwitch.isOn, forKey: "justifyText")
        d.set(customizeSwitch.isOn, forKey: "customizeLayoutEnabled")
        if customizeSwitch.isOn {
            d.set(Double(lineSpacingSlider.value), forKey: "lineHeight")
            d.set(Double(charSpacingSlider.value), forKey: "letterSpacing")
            d.set(Double(wordSpacingSlider.value), forKey: "wordSpacing")
            d.set(Double(marginsSlider.value), forKey: "readerMargins")
        } else {
            d.set(1.6, forKey: "lineHeight")
            d.set(0.0, forKey: "letterSpacing")
            d.set(0.0, forKey: "wordSpacing")
            d.set(0.0, forKey: "readerMargins")
        }
        delegate?.customizeThemeDidUpdate(self)
    }

    private func updatePreview() {
        let d = UserDefaults.standard
        let css = d.string(forKey: "fontFamily") ?? "Georgia"
        let bold = boldSwitch.isOn
        let uiName = (css == "-apple-system") ? nil : css
        let titleFont = uiName.flatMap { UIFont(name: $0, size: 44) } ?? UIFont.systemFont(ofSize: 44)
        let bodyFont = uiName.flatMap { UIFont(name: $0, size: 18) } ?? UIFont.systemFont(ofSize: 18)
        previewTitle.font = titleFont

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(lineSpacingSlider.value) / 1.2
        paragraph.alignment = justifySwitch.isOn ? .justified : .natural
        let charKern = CGFloat(charSpacingSlider.value) * 0.05
        let wordExtra = CGFloat(wordSpacingSlider.value) * 0.15
        let font = bold ? boldVariant(of: bodyFont) : bodyFont
        let text = previewBody.text ?? ""
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
            .kern: charKern,
            .foregroundColor: UIColor.label
        ])
        if wordExtra != 0 {
            let ns = text as NSString
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, range, _, _ in
                let after = range.location + range.length
                if after < ns.length {
                    attributed.addAttribute(.kern, value: charKern + wordExtra, range: NSRange(location: after, length: 1))
                }
            }
        }
        previewBody.attributedText = attributed

        let marginPx = CGFloat(marginsSlider.value) * 1.2
        previewTitleLeading.constant = 20 + marginPx
        previewBodyLeading.constant = 20 + marginPx
        previewBodyTrailing.constant = -(20 + marginPx)
    }

    private func boldVariant(of font: UIFont) -> UIFont {
        if let d = font.fontDescriptor.withSymbolicTraits(.traitBold) {
            return UIFont(descriptor: d, size: font.pointSize)
        }
        return font
    }

    // MARK: - Actions

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func doneTapped() { dismiss(animated: true) }

    @objc private func fontRowTapped() {
        let sheet = UIAlertController(title: "Font", message: nil, preferredStyle: .actionSheet)
        for font in fonts {
            sheet.addAction(UIAlertAction(title: font.name, style: .default) { [weak self] _ in
                guard let self = self else { return }
                UserDefaults.standard.set(font.css, forKey: "fontFamily")
                self.fontValueLabel.text = font.name
                self.updatePreview()
                self.persist()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = fontValueLabel
            pop.sourceRect = fontValueLabel.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func boldChanged() { updatePreview(); persist() }
    @objc private func justifyChanged() { updatePreview(); persist() }
    @objc private func customizeToggleChanged() { updateDimming(); persist() }

    @objc private func lineSpacingChanged() { refreshValueLabels(); updatePreview(); persist() }
    @objc private func charSpacingChanged() { refreshValueLabels(); updatePreview(); persist() }
    @objc private func wordSpacingChanged() { refreshValueLabels(); updatePreview(); persist() }
    @objc private func marginsChanged() { refreshValueLabels(); updatePreview(); persist() }

    @objc private func resetTapped() {
        let d = UserDefaults.standard
        d.set("Georgia", forKey: "fontFamily")
        d.set("normal", forKey: "fontWeight")
        d.set(false, forKey: "justifyText")
        d.set(true, forKey: "customizeLayoutEnabled")
        d.set(1.6, forKey: "lineHeight")
        d.set(0.0, forKey: "letterSpacing")
        d.set(0.0, forKey: "wordSpacing")
        d.set(0.0, forKey: "readerMargins")
        loadState()
        fontValueLabel.text = "Georgia"
        updateDimming()
        updatePreview()
        delegate?.customizeThemeDidUpdate(self)
    }
}
