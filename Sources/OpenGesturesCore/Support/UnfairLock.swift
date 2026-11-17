import os

/// A minimal `os_unfair_lock` wrapper for state touched on the multitouch
/// thread, where a lock costs a few nanoseconds and a queue hop would not.
public final class UnfairLock: @unchecked Sendable {
    private let pointer: os_unfair_lock_t

    public init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    deinit {
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    @inline(__always)
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(pointer)
        defer { os_unfair_lock_unlock(pointer) }
        return try body()
    }
}
