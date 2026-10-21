import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var menuChannel: FlutterMethodChannel?
  private var zoteroChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    let menuChannel = FlutterMethodChannel(
      name: "pdg.menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.menuChannel = menuChannel

    super.awakeFromNib()

    // macOS can keep an old Dock icon cached for the same bundle path across
    // rebuilds. Set the icon explicitly from the current AppIcon.icns so the
    // running app and the pinned Dock tile agree with the bundle.
    // Load the same PNG that Flutter uses for its BrandMark. Reading the
    // image from the app bundle directly avoids the stale IconServices cache
    // that can keep an older owl in the Dock after a rebuild.
    let iconCandidates = [
      Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Frameworks/App.framework/Resources/flutter_assets/assets/brand/app_icon.png"
      ),
      Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/assets/brand/app_icon.png"
      ),
      Bundle.main.bundleURL.appendingPathComponent(
        "Contents/Resources/app_icon.png"
      ),
    ]
    if let iconURL = iconCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
       let icon = NSImage(contentsOf: iconURL) {
      NSApp.applicationIconImage = icon
      NSApp.dockTile.display()
    }

    // A particle-data browser benefits from a wide, readable window while the
    // layout still collapses to a single column below 760 logical pixels.
    // Apply the frame after super.awakeFromNib so a restored frame cannot
    // override the initial size on first launch.
    self.minSize = NSSize(width: 360, height: 560)
    self.title = "Particle Library"
    let visible = (self.screen ?? NSScreen.main)?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
    self.setContentSize(
      NSSize(
        width: min(1400, max(360, visible.width - 80)),
        height: min(900, max(560, visible.height - 80))
      )
    )
    self.setFrameAutosaveName("ParticleLibraryMainWindow")
    self.center()

    let debugChannel = FlutterMethodChannel(
      name: "pdg.debug",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    debugChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "resize",
            let args = call.arguments as? [String: Any],
            let width = args["width"] as? Double,
            let height = args["height"] as? Double else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.setContentSize(NSSize(width: width, height: height))
      self.center()
      result(nil)
    }

    let clipboardChannel = FlutterMethodChannel(
      name: "pdg.clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel.setMethodCallHandler { call, result in
      guard call.method == "copyImage",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            let image = NSImage(contentsOfFile: path) else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      let wrote = pasteboard.writeObjects([image])
      result(wrote)
    }

    // The zotero-inspire target picker is drawn inside Zotero's main window.
    // Bring Zotero forward before asking it to open the picker, then come back
    // to this window once the picker closes.
    let zoteroChannel = FlutterMethodChannel(
      name: "pdg.zotero",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.zoteroChannel = zoteroChannel
    zoteroChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "activateZotero":
        let app = NSRunningApplication
          .runningApplications(withBundleIdentifier: "org.zotero.zotero")
          .first { !$0.isTerminated }
        result(app?.activate(options: [.activateAllWindows]) ?? false)
      case "activateSelf":
        let activated = NSRunningApplication.current.activate(
          options: [.activateAllWindows]
        )
        self?.makeKeyAndOrderFront(nil)
        result(activated)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
  @IBAction func showAppHelp(_ sender: Any?) {
    menuChannel?.invokeMethod("showHelp", arguments: nil)
  }

  @IBAction func showSettings(_ sender: Any?) {
    menuChannel?.invokeMethod("showSettings", arguments: nil)
  }
}
