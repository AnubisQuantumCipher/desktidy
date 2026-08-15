import Darwin
import Foundation

// A single cross-process lock serializes every production movement path.
// The automatic launchd mover and CanonicalApplicationCore.live() both use
// the same app-support lock file, so an Undo transaction cannot overlap a
// watcher sweep or startup reconciliation.
enum MovementProcessLockError: Error, Equatable {
    case busy
    case unavailable(Int32)
}

final class MovementProcessLock {
    let url: URL

    private let stateLock = NSLock()
    private var descriptor: Int32 = -1

    init(url: URL) {
        self.url = url
    }

    func acquire() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard descriptor < 0 else { throw MovementProcessLockError.busy }
        let opened = Darwin.open(url.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard opened >= 0 else { throw MovementProcessLockError.unavailable(errno) }
        guard Darwin.fchmod(opened, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            let failure = errno
            Darwin.close(opened)
            throw MovementProcessLockError.unavailable(failure)
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            Darwin.close(opened)
            if failure == EWOULDBLOCK || failure == EAGAIN {
                throw MovementProcessLockError.busy
            }
            throw MovementProcessLockError.unavailable(failure)
        }
        descriptor = opened
    }

    func release() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
