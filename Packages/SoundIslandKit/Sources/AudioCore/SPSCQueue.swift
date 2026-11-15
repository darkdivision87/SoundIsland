import Atomics

/// Lock-free single-producer / single-consumer ring buffer.
/// Producer: the main thread (UI). Consumer: the audio render thread.
/// Elements must be bitwise-copyable so no retain/release ever happens on the audio thread.
public final class SPSCQueue<Element: BitwiseCopyable>: @unchecked Sendable {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Element>
    private let head = ManagedAtomic<Int>(0) // next slot to read (consumer owns)
    private let tail = ManagedAtomic<Int>(0) // next slot to write (producer owns)

    public init(capacity: Int) {
        precondition(capacity > 1)
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
    }

    deinit { storage.deallocate() }

    /// Producer side. Returns false if the queue is full (command dropped).
    @discardableResult
    public func push(_ element: Element) -> Bool {
        let t = tail.load(ordering: .relaxed)
        let next = (t + 1) % capacity
        if next == head.load(ordering: .acquiring) { return false }
        (storage + t).initialize(to: element)
        tail.store(next, ordering: .releasing)
        return true
    }

    /// Consumer side. Real-time safe.
    @inline(__always)
    public func pop() -> Element? {
        let h = head.load(ordering: .relaxed)
        if h == tail.load(ordering: .acquiring) { return nil }
        let element = (storage + h).move()
        head.store((h + 1) % capacity, ordering: .releasing)
        return element
    }
}

/// Publishes a pair of values from the audio thread to the UI without tearing (sequence lock).
/// Writer: audio thread only. Readers: any thread; they retry while a write is in progress.
public final class SeqLockPair: @unchecked Sendable {
    private let sequence = ManagedAtomic<Int>(0)
    private let a = ManagedAtomic<Int>(0)
    private let b = ManagedAtomic<Int>(0)

    public init() {}

    @inline(__always)
    public func write(_ first: Int, _ second: Int) {
        sequence.wrappingIncrement(ordering: .acquiringAndReleasing) // odd: writing
        a.store(first, ordering: .relaxed)
        b.store(second, ordering: .relaxed)
        sequence.wrappingIncrement(ordering: .acquiringAndReleasing) // even: stable
    }

    public func read() -> (Int, Int) {
        while true {
            let s1 = sequence.load(ordering: .acquiring)
            if s1 & 1 == 1 { continue }
            let first = a.load(ordering: .relaxed)
            let second = b.load(ordering: .relaxed)
            if sequence.load(ordering: .acquiring) == s1 { return (first, second) }
        }
    }
}
