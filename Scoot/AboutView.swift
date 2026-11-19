import SwiftUI
import OSLog

struct AboutView: View {

    var body: some View {
        VStack(spacing: 4) {
            Group {
                Image(nsImage: NSImage(named: "AppIcon")!)
                Text(Bundle.main.displayName!)
                    .font(.system(size: 26, weight: .heavy))
                Text("Press anything on your Mac by name")
                    .font(.system(size: 20, weight: .light)).italic()
                Text("Version \(Bundle.main.version)")
                    .font(.system(size: 16, weight: .light))
                Spacer()
            }
            Group {
                Spacer()
                Text("Pressto lets you reach any button, menu or tab from the keyboard: search it by name, jump to it by label, or steer the pointer there.\n\nBuilt on [Scoot](https://github.com/mjrusso/scoot) by Michael Russo.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            Group {
                Spacer()
                Link("pressto.app", destination: URL(string: "https://pressto.app")! )
                Link("github.com/nillebco/pressto", destination: URL(string: "https://github.com/nillebco/pressto")! )
                Spacer()
            }
            Group {
                Spacer()
                HStack(spacing: 20)  {
                    Button("Credits", action: showCreditsAction)
                        .buttonStyle(.borderless)
                    Button("License", action: showLicenseAction)
                        .buttonStyle(.borderless)
                }
                Spacer()
                Text(Bundle.main.copyright!)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    func showCreditsAction() {
        OSLog.main.log("Showing credits window.")
        openWindow(rootView: CreditsView(), title: "\(Bundle.main.displayName!) Credits")
    }

    func showLicenseAction() {
        OSLog.main.log("Showing license window.")
        openWindow(rootView: LicenseView(), title: "\(Bundle.main.displayName!) License")
    }

    func openWindow<Content>(rootView: Content, title: String) where Content : View {

        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.closable, .titled]
        window.titlebarAppearsTransparent = true
        window.title = title

        let controller = NSWindowController(window: window)
        controller.showWindow(self)
    }

}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
