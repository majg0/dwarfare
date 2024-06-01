//
//  AppDelegate.swift
//  macos
//
//  Created by Martin Grönlund on 2024-06-02.
//

import Cocoa
import Dwarven;

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    @IBOutlet var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Dwarven.`init`();

        let arguments = CommandLine.arguments
        print("Command-line arguments: \(arguments)")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        Dwarven.kill();
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
}
