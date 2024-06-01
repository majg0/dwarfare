//
//  GameViewController.swift
//  macos
//
//  Created by Martin Grönlund on 2024-06-02.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewWillAppear() {
        super.viewWillAppear()

        // TODO: get via Dwarven
        let windowTitle = "Dwarfare";
        if let window = view.window {
            window.title = windowTitle
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer

        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleKeyDown)
        NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: handleKeyUp)
    }

    func handleKeyDown(event: NSEvent) -> NSEvent? {
        if let characters = event.characters {
            print("Key down: \(characters)")
        }
        return event
    }

    func handleKeyUp(event: NSEvent) -> NSEvent? {
        if let characters = event.characters {
            print("Key up: \(characters)")
        }
        return event
    }
}
