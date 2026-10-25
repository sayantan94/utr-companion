import Foundation
import Testing
@testable import UTRCore

private func identity(_ id: Int = 1094863410) throws -> RecorderSnapshot {
    try JSONDecoder().decode(RecorderSnapshot.self, from: Data("{\"system_id\":\(id),\"fw_version\":\"test\",\"hw_version\":\"test\",\"rec_gsensor_lv_driving\":2,\"rec_gsensor_lv_parking\":3,\"rec_radar_lv\":3}".utf8))
}
@Test func framingUsesParamsHeader() throws {
    let api = try UTR2Requests(address: "192.168.1.1")
    let r = api.settings()
    #expect(r.httpMethod == "POST"); #expect(r.url?.query == nil)
    #expect(r.value(forHTTPHeaderField: "Params") == "?settings")
    let s = try api.sensors(driving: 1, parking: 4, radar: 2, identity: identity())
    #expect(s.value(forHTTPHeaderField: "Params") == "?rec_gsensor_lv_driving=1&rec_gsensor_lv_parking=4&rec_radar_lv=2")
}
@Test func clockPreservesLocalOffsetIncludingDST() throws {
    let date = ISO8601DateFormatter().date(from: "2026-10-25T18:42:00Z")!
    #expect(UTR2Requests.clockValue(date: date, zone: TimeZone(identifier: "America/Los_Angeles")!) == "2026-10-25T11:42:00.000Z-0700")
    #expect(UTR2Requests.clockValue(date: date, zone: TimeZone(identifier: "Asia/Kolkata")!) == "2026-10-26T00:12:00.000Z+0530")
    let r = try UTR2Requests(address: "192.168.1.1").clock(date: date, zone: TimeZone(identifier: "Asia/Kolkata")!, identity: identity())
    #expect(r.url!.absoluteString.contains("%2B0530"))
}
@Test func rejectsUnknownDeviceAndExternalAddresses() throws {
    #expect(throws: RecorderError.self) { try UTR2Requests(address: "8.8.8.8") }
    #expect(throws: RecorderError.self) { try UTR2Requests(address: "192.168.1.1@evil.com") }
    #expect(throws: RecorderError.self) { try UTR2Requests(address: "192.168.1.1").clock(identity: identity(1094863153)) }
    #expect(throws: RecorderError.self) { try UTR2Requests(address: "192.168.1.1").sensors(driving: 6, parking: 3, radar: 3, identity: identity()) }
}
@Test func dateValidationDoesNotInventCaptureTime() {
    #expect(Clip.filenameTime("20310230_101936_front.MP4") == nil)
    #expect(Clip.filenameTime("20310401_101936D.MP4") == "2031-04-01T10:19:36")
    var front = Clip(name: "20310401_101936_front.MP4", camera: .front)
    let rear = Clip(name: "20310401_101936_rear.MP4", camera: .rear)
    front.correctedWallTime = "2026-10-25T10:19:36"
    #expect(front.recordedWallTime == "2031-04-01T10:19:36")
    #expect(rear.correctedWallTime == nil)
    let before = front.savedAt; front.correctedWallTime = nil
    #expect(front.effectiveTime == front.recordedWallTime); #expect(front.savedAt == before)
}
