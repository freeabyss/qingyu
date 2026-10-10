import os

/// macOS 12–compatible stand-in for `OSAllocatedUnfairLock` (macOS 13+).
///
/// Search sources keep their index state in their own properties and use this
/// lock purely for mutual exclusion, so a `Void`-state lock exposing the same
/// `withLock` shape is sufficient. The `os_unfair_lock` storage is heap
/// allocated to keep its address stable for the lifetime of the lock.
final class UnfairLock: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<os_unfair_lock>

    init() {
        storage = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        storage.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }

    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(storage)
        defer { os_unfair_lock_unlock(storage) }
        return try body()
    }
}
