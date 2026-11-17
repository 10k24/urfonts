import AppKit
import SwiftUI

/// Replaces the default About item so the credits can name the studio and link
/// to the repository. Version, build and copyright still come from Info.plist.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(Messages.About.menuItem) {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationName: Messages.About.applicationName,
                    .credits: credits,
                ])
            }
        }
    }

    private var credits: NSAttributedString {
        let text = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        text.append(NSAttributedString(
            string: Messages.About.byline + "\n",
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: NSFont.smallSystemFontSize,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        text.append(NSAttributedString(
            string: Messages.About.summary + "\n",
            attributes: body
        ))
        if let stamp = Bundle.main.object(
            forInfoDictionaryKey: "UrFontsBuildStamp"
        ) as? String {
            text.append(NSAttributedString(
                string: stamp + "\n",
                attributes: body
            ))
        }
        text.append(NSAttributedString(
            string: Messages.About.repository,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.linkColor,
                // Fixed literal; URL(string:) cannot fail for this value.
                .link: URL(string: "https://github.com/10k24/urfonts")!,
            ]
        ))
        return text
    }
}
