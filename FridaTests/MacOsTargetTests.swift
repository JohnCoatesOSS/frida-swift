//
//  MacOsTargetTests.swift
//  Created on 6/24/19
//

import XCTest
@testable import Frida

class MacOsTargetTests: XCTestCase {

    lazy var manager = DeviceManager()
    var localDevice: Device!
    var pid: UInt!
    var session: Session!
    var script: Script!
    lazy var scriptDelegate: FridaScriptDelegate = FridaScriptDelegate()

    private func getProductsConfigurationDirectory() -> URL {
        let bundlePath = Bundle(for: MacOsTargetTests.self).bundlePath
        let url = URL(fileURLWithPath: bundlePath)
        return url.deletingLastPathComponent()
    }

    private func getSourceRoot() -> URL {
        let fileManager = FileManager.default
        var url = URL(fileURLWithPath: #file)
        while fileManager.fileExists(atPath: url.appendingPathComponent(".git").path) == false {
            url = url.deletingLastPathComponent()

            if url.pathComponents.count == 0 {
                url = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
                break
            }
        }

        return url
    }

    override func setUp() {
    }

    private func spawnWith(script scriptContents: String) {
        var localDeviceMaybe: Device?
        blocking { semaphore in
            self.manager.enumerateDevices { result in
                let devices = try! result()
                let localDevice = devices.filter { $0.kind == Device.Kind.local }.first!
                localDeviceMaybe = localDevice
                semaphore.signal()
            }
        }

        XCTAssertNotNil(localDeviceMaybe)
        self.localDevice = localDeviceMaybe
        let binary = getProductsConfigurationDirectory().appendingPathComponent("TestTarget")

        var pidMaybe: UInt?
        blocking { semaphore in
            self.localDevice.spawn(binary.path) { result in
                do {
                    pidMaybe = try result()
                } catch let error {
                    print("Couldn't launch, error: \(error)")
                }

                semaphore.signal()
            }
        }

        XCTAssertNotNil(pidMaybe)
        pid = pidMaybe

        var sessionMaybe: Session?

        blocking { semaphore in
            self.localDevice.attach(self.pid) { (result) in
                sessionMaybe = try? result()
                semaphore.signal()
            }
        }
        XCTAssertNotNil(sessionMaybe)
        session = sessionMaybe

        var scriptMaybe: Script?

        blocking { semaphore in
            self.session.createScript(scriptContents) { (result) in
                scriptMaybe = try! result()
                semaphore.signal()
            }
        }

        XCTAssertNotNil(scriptMaybe)
        script = scriptMaybe
        script.delegate = scriptDelegate
    }

    override func tearDown() {
        manager.close()
    }

    func testReceiveMessage() {
        spawnWith(script: #"console.log("done")"#)
        let expectation = self.expectation(description: "Received message")

        scriptDelegate.onMessage = { message in
            if case let.regular(_, payload) = message, payload == "done" {
                print("message: \(payload)")
                expectation.fulfill()
            }
        }

        script.load()
        localDevice.resume(pid)

        self.waitForExpectations(timeout: 2.0, handler: nil)
    }

    func testRpcCall() throws {
        let scriptContents = """
        rpc.exports = {
            add: function (a, b) {
                return a + b;
            }
        };
        """
        spawnWith(script: scriptContents)

        script.load()

        let expectation = self.expectation(description: "Received RPC result.")

        let add = script.exports.add

        add(5, 3).onResult(as: Int.self) { result in
            switch result {
            case let .success(value):
                XCTAssertEqual(value, 5 + 3, "RPC Function called successfully.")
            case let .error(error):
                XCTFail(error.localizedDescription)
            }
            expectation.fulfill()
        }


        let addSync: RpcFunctionSync<Int> = script.exports.sync.add
        try XCTAssertEqual(addSync(5, 3), 5 + 3)

        self.waitForExpectations(timeout: 2.0, handler: nil)

        session.detach()
    }

}

fileprivate func blocking(closure: @escaping (_ semaphore: NonRunLoopBlockingSemaphore) -> Void) {
    let semaphore = NonRunLoopBlockingSemaphore()
    closure(semaphore)

    semaphore.wait()
}

enum FridaScriptMessage {
    case regular(type: String, payload: String)
    case other(message: Any, data: Data?)
}

class FridaScriptDelegate: NSObject, ScriptDelegate {
    var onMessage: ((FridaScriptMessage) -> Void)?

    @objc func script(_ script: Script, didReceiveMessage message: Any, withData data: Data?) {
        guard let dict = message as? [String: String] else {
            onMessage?(.other(message: message, data: data))
            return
        }

        let typeMaybe = dict["type"]
        let payloadMaybe = dict["payload"]

        guard let type = typeMaybe, let payload = payloadMaybe else {
            print("Couldn't get type and payload")
            return
        }

        onMessage?(.regular(type: type, payload: payload))
    }
}
