import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  // Regression for #538: PushKit terminates the process (SIGABRT in
  // `_terminateAppIfThereAreUnhandledVoIPPushes`) if a VoIP push completes
  // without reporting a CallKit call. Every classification — including pushes
  // we intend to ignore — must therefore still report a call, i.e. it must
  // never resolve to a "silent drop". These tests assert that malformed /
  // filtered payloads map to `.reportAndEnd` rather than being dropped.

  func testMissingRoomIdReportsAndEnds() {
    let outcome = AppDelegate.classifyVoipPush([
      "notification": [
        "event_type": "org.matrix.msc3401.call.member",
        "call_id": "abc",
      ]
    ])
    guard case .reportAndEnd = outcome else {
      return XCTFail("missing room_id must report+end, got \(outcome)")
    }
  }

  func testWrongEventTypeReportsAndEnds() {
    let outcome = AppDelegate.classifyVoipPush([
      "notification": [
        "room_id": "!room:server",
        "event_type": "m.call.hangup",
        "call_id": "abc",
      ]
    ])
    guard case .reportAndEnd(let handle, _) = outcome else {
      return XCTFail("wrong event_type must report+end, got \(outcome)")
    }
    XCTAssertEqual(handle, "!room:server")
  }

  func testMissingCallIdReportsAndEnds() {
    let outcome = AppDelegate.classifyVoipPush([
      "notification": [
        "room_id": "!room:server",
        "event_type": "org.matrix.msc3401.call.member",
      ]
    ])
    guard case .reportAndEnd = outcome else {
      return XCTFail("missing call_id must report+end, got \(outcome)")
    }
  }

  func testValidCallMemberPushShowsIncomingCall() {
    let outcome = AppDelegate.classifyVoipPush([
      "notification": [
        "room_id": "!room:server",
        "event_type": "org.matrix.msc3401.call.member",
        "call_id": "abc",
        "sender_display_name": "Alice",
        "is_video": "true",
      ]
    ])
    guard case .showIncomingCall(let roomId, let name, _, let isVideo) = outcome else {
      return XCTFail("valid call-member push must show incoming call, got \(outcome)")
    }
    XCTAssertEqual(roomId, "!room:server")
    XCTAssertEqual(name, "Alice")
    XCTAssertTrue(isVideo)
  }

  func testFlatPayloadWithoutNotificationEnvelope() {
    let outcome = AppDelegate.classifyVoipPush([
      "room_id": "!room:server",
      "event_type": "org.matrix.msc3401.call.member",
      "call_id": "abc",
    ])
    guard case .showIncomingCall = outcome else {
      return XCTFail("flat payload must be classified, got \(outcome)")
    }
  }
}
