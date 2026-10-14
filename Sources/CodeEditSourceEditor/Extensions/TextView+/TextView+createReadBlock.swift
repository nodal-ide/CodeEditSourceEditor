//
//  TextView+createReadBlock.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 5/20/23.
//

import Foundation
import CodeEditTextView
import SwiftTreeSitter

extension TextView {
    /// Creates a block for safely reading data into a parser's read block.
    ///
    /// If the thread is the main queue, executes synchronously.
    /// Otherwise it will block the calling thread and execute the block on the main queue, returning control to the
    /// calling queue when the block is finished running.
    ///
    /// - Returns: A new block for reading contents for tree-sitter.
    func createReadBlock() -> Parser.ReadBlock {
        return { [weak self] byteOffset, _ in
            let workItem: () -> Data? = {
                let limit = self?.documentRange.length ?? 0
                let location = byteOffset / 2
                let end = min(location + (TreeSitterClient.Constants.charsToReadInBlock), limit)
                if location > end || self == nil {
                    // Ignore and return nothing, tree-sitter's internal tree can be incorrect in some situations.
                    return nil
                }
                let range = NSRange(location..<end)
                return self?.textStorage.substring(from: range)?.data(using: String.nativeUTF16Encoding)
            }
            return DispatchQueue.waitMainIfNot(workItem)
        }
    }
    /// Creates a block for safely reading data for a text provider.
    ///
    /// If the thread is the main queue, executes synchronously.
    /// Otherwise it will block the calling thread and execute the block on the main queue, returning control to the
    /// calling queue when the block is finished running.
    ///
    /// - Returns: A new block for reading contents for tree-sitter.
    func createReadCallback() -> SwiftTreeSitter.Predicate.TextProvider {
        return { [weak self] range, _ in
            let workItem: () -> String? = {
                self?.textStorage.substring(from: range)
            }
            return DispatchQueue.waitMainIfNot(workItem)
        }
    }

    /// Creates a read block that snapshots the document **once** and then serves every chunk from that immutable
    /// snapshot.
    ///
    /// The default ``createReadBlock()`` hops to the main queue (`main.sync`) for *every* chunk it returns and for
    /// every injection text lookup. During the initial parse of a document that's hundreds of synchronous main-thread
    /// round-trips, which is what makes a freshly opened file feel like it lags while the language initializes.
    ///
    /// This variant performs a single main-thread rendezvous — lazily, on the first read — copies the document, and
    /// then serves all subsequent reads from the in-memory snapshot with no further main-thread hops.
    ///
    /// Use this for the initial parse, where the document is stable. Incremental parses must keep using
    /// ``createReadBlock()`` so they observe live edits.
    ///
    /// - Returns: A block that reads from a single, immutable snapshot of the document.
    func createSnapshotReadBlock() -> Parser.ReadBlock {
        var snapshot: Data?
        // The snapshot is UTF-16, so each character is two bytes.
        let chunkBytes = TreeSitterClient.Constants.charsToReadInBlock * 2

        return { [weak self] byteOffset, _ in
            if snapshot == nil {
                snapshot = DispatchQueue.waitMainIfNot { [weak self] in
                    guard let string = self?.textStorage.string else { return Data() }
                    return string.data(using: String.nativeUTF16Encoding) ?? Data()
                }
            }
            guard let snapshot, byteOffset >= 0, byteOffset < snapshot.count else { return nil }
            let end = min(byteOffset + chunkBytes, snapshot.count)
            return snapshot.subdata(in: byteOffset..<end)
        }
    }

    /// Snapshot variant of ``createReadCallback()``, used alongside ``createSnapshotReadBlock()`` for the initial
    /// parse so predicate/injection text lookups don't hop to the main thread for every match.
    ///
    /// - Returns: A text provider that reads from a single, immutable snapshot of the document.
    func createSnapshotReadCallback() -> SwiftTreeSitter.Predicate.TextProvider {
        var snapshot: NSString?

        return { [weak self] range, _ in
            if snapshot == nil {
                snapshot = DispatchQueue.waitMainIfNot { [weak self] in
                    (self?.textStorage.string ?? "") as NSString
                }
            }
            guard let snapshot, range.location >= 0, NSMaxRange(range) <= snapshot.length else { return nil }
            return snapshot.substring(with: range)
        }
    }
}
