import Foundation

class NonRunLoopBlockingSemaphore {
    var signaled = false

    func signal() {
        signaled = true
    }

    func wait() {
        while signaled == false {
            RunLoop.current.run(until: Date())
        }
    }
}
