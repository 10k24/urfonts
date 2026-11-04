import Foundation
import UrFontsFixtures

/// Writes the fixture library. Not part of the app.
///
/// Usage: FixtureGen [--out <dir>] [--count <n>] [--subdirs <n>]
/// Default output is build/fixtures/library.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var outPath = "build/fixtures/library"
var count = 23_000
var subdirCount = 100

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--out":
        guard let value = arguments.next() else { fail("--out needs a path") }
        outPath = value
    case "--count":
        guard let value = arguments.next(), let parsed = Int(value), parsed > 0 else {
            fail("--count needs a positive integer")
        }
        count = parsed
    case "--subdirs":
        guard let value = arguments.next(), let parsed = Int(value), parsed > 0 else {
            fail("--subdirs needs a positive integer")
        }
        subdirCount = parsed
    case "--help", "-h":
        print("usage: FixtureGen [--out <dir>] [--count <n>] [--subdirs <n>]")
        exit(0)
    default:
        fail("unknown argument: \(argument)")
    }
}

let root = URL(fileURLWithPath: outPath, isDirectory: true)
let manager = FileManager.default

do {
    if manager.fileExists(atPath: root.path) {
        try manager.removeItem(at: root)
    }
    try manager.createDirectory(at: root, withIntermediateDirectories: true)

    var directories: [URL] = []
    for index in 0..<subdirCount {
        let directory = root.appendingPathComponent(String(format: "sub-%03d", index))
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
    }

    let started = Date()
    for index in 0..<count {
        let spec = MinimalFontSpec(index: index)
        let data = MinimalFont.data(for: spec)
        let directory = directories[index % directories.count]
        let url = directory.appendingPathComponent("\(spec.postscriptName).ttf")
        try data.write(to: url, options: .atomic)
        if index > 0, index % 1_000 == 0 {
            print("wrote \(index)")
        }
    }
    let elapsed = Date().timeIntervalSince(started)
    let megabytes = Double(count * 800) / 1_000_000
    print(String(format: "wrote %d files to %@ in %.2f s (about %.1f MB)",
                 count, root.path, elapsed, megabytes))
} catch {
    fail("fixture generation failed: \(error)")
}
