import AppKit

let application = NSApplication.shared
let applicationDelegate = PreviewAppDelegate()

application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
application.run()
