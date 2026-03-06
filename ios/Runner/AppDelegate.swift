import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var screenProtectionOverlay: UIView?
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Firebase BEFORE anything else so it's ready to receive APNs token
    FirebaseApp.configure()

    // Set UNUserNotificationCenter delegate BEFORE plugin registration
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    GeneratedPluginRegistrant.register(with: self)

    // Register for remote notifications (APNs)
    application.registerForRemoteNotifications()

    // Set up platform channels
    let controller = window?.rootViewController as! FlutterViewController

    // Background download support
    let bgChannel = FlutterMethodChannel(
      name: "com.pgme.app/background_download",
      binaryMessenger: controller.binaryMessenger
    )
    bgChannel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "beginBackgroundTask":
        self?.beginBackgroundTask()
        result(true)
      case "endBackgroundTask":
        self?.endBackgroundTask()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Storage info channel
    let storageChannel = FlutterMethodChannel(
      name: "com.pgme.app/storage_info",
      binaryMessenger: controller.binaryMessenger
    )
    storageChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getFreeDiskSpace":
        result(self.getFreeDiskSpaceMB())
      case "getTotalDiskSpace":
        result(self.getTotalDiskSpaceMB())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Detect screen recording — show black overlay
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenCaptureChanged),
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )

    // Check if already recording on launch
    if UIScreen.main.isCaptured {
      screenCaptureChanged()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Background Download Support

  private func beginBackgroundTask() {
    guard backgroundTaskId == .invalid else { return }
    backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "VideoDownload") {
      // Expiration handler — OS is about to suspend us
      self.endBackgroundTask()
    }
    debugPrint("AppDelegate: Background task started (id: \(backgroundTaskId.rawValue))")
  }

  private func endBackgroundTask() {
    guard backgroundTaskId != .invalid else { return }
    debugPrint("AppDelegate: Background task ended (id: \(backgroundTaskId.rawValue))")
    UIApplication.shared.endBackgroundTask(backgroundTaskId)
    backgroundTaskId = .invalid
  }

  // MARK: - Storage Info

  private func getFreeDiskSpaceMB() -> Double {
    do {
      let attrs = try FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory()
      )
      if let freeSize = attrs[.systemFreeSize] as? Int64 {
        return Double(freeSize) / (1024.0 * 1024.0)
      }
    } catch {
      debugPrint("AppDelegate: Failed to get free disk space - \(error)")
    }
    return -1
  }

  private func getTotalDiskSpaceMB() -> Double {
    do {
      let attrs = try FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory()
      )
      if let totalSize = attrs[.systemSize] as? Int64 {
        return Double(totalSize) / (1024.0 * 1024.0)
      }
    } catch {
      debugPrint("AppDelegate: Failed to get total disk space - \(error)")
    }
    return -1
  }

  // MARK: - Screen Recording Prevention

  @objc private func screenCaptureChanged() {
    DispatchQueue.main.async {
      if UIScreen.main.isCaptured {
        self.showRecordingOverlay()
      } else {
        self.removeRecordingOverlay()
      }
    }
  }

  private func showRecordingOverlay() {
    guard screenProtectionOverlay == nil, let window = self.window else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.backgroundColor = .black
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.tag = 9999

    let label = UILabel()
    label.text = "Screen recording is not allowed"
    label.textColor = .white
    label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    overlay.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
    ])

    window.addSubview(overlay)
    screenProtectionOverlay = overlay
  }

  private func removeRecordingOverlay() {
    screenProtectionOverlay?.removeFromSuperview()
    screenProtectionOverlay = nil
  }

  // MARK: - APNs

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}
