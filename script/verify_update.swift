import Foundation
import CryptoKit

guard CommandLine.arguments.count == 5 else { exit(2) }
let archive = URL(fileURLWithPath: CommandLine.arguments[1])
let appcast = URL(fileURLWithPath: CommandLine.arguments[2])
let config = URL(fileURLWithPath: CommandLine.arguments[3])
let expectedURL = CommandLine.arguments[4]
let settings = try PropertyListSerialization.propertyList(from: Data(contentsOf: config), format: nil) as? [String: Any]
guard let encodedKey = settings?["SUPublicEDKey"] as? String,
      let rawKey = Data(base64Encoded: encodedKey) else { exit(1) }
let document = try XMLDocument(contentsOf: appcast, options: [.nodeLoadExternalEntitiesNever])
let enclosures = try document.nodes(forXPath: "//*[local-name()='enclosure']")
guard enclosures.count == 1, let enclosure = enclosures.first as? XMLElement,
      enclosure.attribute(forName: "url")?.stringValue == expectedURL,
      let encodedSignature = enclosure.attribute(forLocalName: "edSignature", uri: "http://www.andymatuschak.org/xml-namespaces/sparkle")?.stringValue,
      let signature = Data(base64Encoded: encodedSignature) else { exit(1) }
let bytes = try Data(contentsOf: archive)
guard enclosure.attribute(forName: "length")?.stringValue == String(bytes.count),
      try Curve25519.Signing.PublicKey(rawRepresentation: rawKey).isValidSignature(signature, for: bytes) else { exit(1) }
print("Archive signature, size and download URL verified against the public trust anchor.")
