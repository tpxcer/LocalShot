import Foundation

public enum LocalFileExporter {
    public static func exportCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let destination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
        guard source != destination else {
            return
        }

        try exportGeneratedFile(to: destination) { temporaryURL in
            try FileManager.default.copyItem(at: source, to: temporaryURL)
        }
    }

    public static func exportGeneratedFile(
        to destinationURL: URL,
        writer: (URL) throws -> Void
    ) throws {
        let destination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
        let fileManager = FileManager.default
        let replacementDirectory = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
        let temporaryURL = replacementDirectory
            .appendingPathComponent(destination.lastPathComponent)
        defer {
            try? fileManager.removeItem(at: replacementDirectory)
        }

        try writer(temporaryURL)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
    }
}
