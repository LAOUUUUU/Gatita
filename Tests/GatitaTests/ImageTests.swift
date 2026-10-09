//
//  ImageTests.swift
//  GatitaTests
//

import XCTest
@testable import Gatita

/// Pictures in chat: how a message with a picture is sent, and that saved chats with and without pictures load.
final class ImageTests: XCTestCase {
    private func encodedJSON(_ wire: WireMessage) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try encoder.encode(wire), encoding: .utf8) ?? ""
    }

    func testAMessageWithoutPicturesIsSentAsPlainText() throws {
        let json = try encodedJSON(GatitaClient.wire(ChatMessage(role: "user", content: "hi")))
        XCTAssertEqual(json, #"{"content":"hi","role":"user"}"#)
    }

    func testAPictureIsSentAsADataURLNextToTheText() throws {
        let image = ChatImage(name: "a.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let message = ChatMessage(role: "user", content: "what is this?", images: [image])
        let json = try encodedJSON(GatitaClient.wire(message))
        XCTAssertEqual(json, #"{"content":[{"text":"what is this?","type":"text"},{"image_url":{"url":"data:image/png;base64,AQID"},"type":"image_url"}],"role":"user"}"#)
    }

    func testAChatSavedBeforePicturesStillLoads() throws {
        let saved = try JSONEncoder().encode(ChatMessage(role: "user", content: "an old chat"))
        let loaded = try JSONDecoder().decode(ChatMessage.self, from: saved)
        XCTAssertEqual(loaded.content, "an old chat")
        XCTAssertTrue(loaded.attachedImages.isEmpty)
    }

    func testPicturesSurviveSavingTheChat() throws {
        let image = ChatImage(name: "a.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let message = ChatMessage(role: "user", content: "look", images: [image])
        let loaded = try JSONDecoder().decode(ChatMessage.self, from: try JSONEncoder().encode(message))
        XCTAssertEqual(loaded.attachedImages, [image])
    }
}
