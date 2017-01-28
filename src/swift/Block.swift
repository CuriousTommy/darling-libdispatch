//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import CDispatch

public struct DispatchWorkItemFlags : OptionSet, RawRepresentable {
	public let rawValue: UInt
	public init(rawValue: UInt) { self.rawValue = rawValue }

	public static let barrier = DispatchWorkItemFlags(rawValue: 0x1)

	@available(OSX 10.10, iOS 8.0, *)
	public static let detached = DispatchWorkItemFlags(rawValue: 0x2)

	@available(OSX 10.10, iOS 8.0, *)
	public static let assignCurrentContext = DispatchWorkItemFlags(rawValue: 0x4)

	@available(OSX 10.10, iOS 8.0, *)
	public static let noQoS = DispatchWorkItemFlags(rawValue: 0x8)

	@available(OSX 10.10, iOS 8.0, *)
	public static let inheritQoS = DispatchWorkItemFlags(rawValue: 0x10)

	@available(OSX 10.10, iOS 8.0, *)
	public static let enforceQoS = DispatchWorkItemFlags(rawValue: 0x20)
}

@available(OSX 10.10, iOS 8.0, *)
public class DispatchWorkItem {
	internal var _block: _DispatchBlock
	internal var _group: DispatchGroup?

	public init(group: DispatchGroup? = nil, qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], block: @convention(block) () -> ()) {
		_block =  dispatch_block_create_with_qos_class(dispatch_block_flags_t(flags.rawValue),
			qos.qosClass.rawValue.rawValue, Int32(qos.relativePriority), block)
	}

	// Used by DispatchQueue.synchronously<T> to provide a @noescape path through
	// dispatch_block_t, as we know the lifetime of the block in question.
	internal init(flags: DispatchWorkItemFlags = [], noescapeBlock: @noescape () -> ()) {
		_block = _swift_dispatch_block_create_noescape(dispatch_block_flags_t(flags.rawValue), noescapeBlock)
	}

	public func perform() {
		if let g = _group { 
			g.enter() 
			defer { g.leave() }
		}
		_block()
	}

	public func wait() {
		_ = dispatch_block_wait(_block, DispatchTime.distantFuture.rawValue)
	}

	public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
		return dispatch_block_wait(_block, timeout.rawValue) == 0 ? .Success : .TimedOut
	}

	public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
		return dispatch_block_wait(_block, wallTimeout.rawValue) == 0 ? .Success : .TimedOut
	}

	public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue, execute: @convention(block) () -> Void) {
		if qos != .unspecified || !flags.isEmpty {
			let item = DispatchWorkItem(qos: qos, flags: flags, block: execute)
			dispatch_block_notify(_block, queue.__wrapped, item._block)
		} else {
			dispatch_block_notify(_block, queue.__wrapped, execute)
		}
	}

	public func notify(queue: DispatchQueue, execute: DispatchWorkItem) {
		dispatch_block_notify(_block, queue.__wrapped, execute._block)
	}

	public func cancel() {
		dispatch_block_cancel(_block)
	}

	public var isCancelled: Bool {
		return dispatch_block_testcancel(_block) != 0
	}
}

@available(OSX 10.10, iOS 8.0, *)
public extension DispatchWorkItem {
	@available(*, deprecated, renamed: "DispatchWorkItem.wait(self:wallTimeout:)")
	public func wait(timeout: DispatchWallTime) -> Int {
		switch wait(wallTimeout: timeout) {
		case .Success: return 0
		case .TimedOut: return DispatchTimeoutResult.KERN_OPERATION_TIMED_OUT
		}
	}
}

/// The dispatch_block_t typealias is different from usual closures in that it
/// uses @convention(block). This is to avoid unnecessary bridging between
/// C blocks and Swift closures, which interferes with dispatch APIs that depend
/// on the referential identity of a block. Particularly, dispatch_block_create.
internal typealias _DispatchBlock = @convention(block) () -> Void
internal typealias dispatch_block_t = @convention(block) () -> Void

@_silgen_name("_swift_dispatch_block_create_noescape")
internal func _swift_dispatch_block_create_noescape(_ flags: dispatch_block_flags_t, _ block: @noescape () -> ()) -> _DispatchBlock
