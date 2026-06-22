import Foundation
import ZIPFoundation

struct EPUBSpineItem: Identifiable {
    let id: String
    let href: String   // absolute path inside the unzipped archive
}

struct EPUBManifest {
    let spineItems: [EPUBSpineItem]
    let basePath: URL  // directory containing the OPF file
}

enum EPUBError: Error {
    case notFound(String)
    case parseFailure(String)
}

struct EPUBParser {

    /// Unzip `epubURL` into `destinationURL` (created if missing), then parse the OPF spine.
    static func parse(epubURL: URL, into destinationURL: URL) throws -> EPUBManifest {
        let fm = FileManager.default

        if !fm.fileExists(atPath: destinationURL.path) {
            try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }

        // Unzip (idempotent-ish: overwrite existing)
        try fm.unzipItem(at: epubURL, to: destinationURL)

        // Locate container.xml
        let containerURL = destinationURL.appendingPathComponent("META-INF/container.xml")
        guard fm.fileExists(atPath: containerURL.path) else {
            throw EPUBError.notFound("META-INF/container.xml")
        }
        let containerData = try Data(contentsOf: containerURL)
        let opfPath = try parseContainerXML(containerData)

        let opfURL = destinationURL.appendingPathComponent(opfPath)
        guard fm.fileExists(atPath: opfURL.path) else {
            throw EPUBError.notFound(opfPath)
        }
        let opfData = try Data(contentsOf: opfURL)
        let basePath = opfURL.deletingLastPathComponent()

        let spineItems = try parseOPF(opfData, basePath: basePath)
        return EPUBManifest(spineItems: spineItems, basePath: basePath)
    }

    // MARK: - Private

    private static func parseContainerXML(_ data: Data) throws -> String {
        let parser = ContainerXMLParser(data: data)
        try parser.parse()
        guard let path = parser.opfPath else {
            throw EPUBError.parseFailure("No rootfile path in container.xml")
        }
        return path
    }

    private static func parseOPF(_ data: Data, basePath: URL) throws -> [EPUBSpineItem] {
        let parser = OPFParser(data: data, basePath: basePath)
        try parser.parse()
        return parser.spineItems
    }
}

// MARK: - SAX Parsers

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    var opfPath: String?
    private var error: Error?

    init(data: Data) { self.data = data }

    func parse() throws {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        if let e = error { throw e }
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if element == "rootfile", let path = attributes["full-path"] {
            opfPath = path
        }
    }
}

private final class OPFParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let basePath: URL
    private var error: Error?

    // manifest: id -> href
    private var manifest: [String: String] = [:]
    // spine: ordered idrefs
    private var spineRefs: [String] = []
    private var inSpine = false

    var spineItems: [EPUBSpineItem] = []

    init(data: Data, basePath: URL) {
        self.data = data
        self.basePath = basePath
    }

    func parse() throws {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.parse()
        if let e = error { throw e }

        spineItems = spineRefs.compactMap { idref in
            guard let href = manifest[idref] else { return nil }
            let absoluteURL = basePath.appendingPathComponent(href)
            return EPUBSpineItem(id: idref, href: absoluteURL.path)
        }
    }

    func parser(_ parser: XMLParser, didStartElement element: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch element {
        case "item":
            if let id = attributes["id"], let href = attributes["href"] {
                manifest[id] = href
            }
        case "spine":
            inSpine = true
        case "itemref" where inSpine:
            if let idref = attributes["idref"] {
                spineRefs.append(idref)
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String,
                namespaceURI: String?, qualifiedName: String?) {
        if element == "spine" { inSpine = false }
    }
}
