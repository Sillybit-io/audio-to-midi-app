import Foundation
import Testing
@testable import SillyMIDITools

struct EngineProtocolTests {
    @Test func decodesDevices() throws {
        let line = #"{"type":"devices","auto":0,"devices":[{"index":0,"name":"CPU","backend":"CPU","integrated":false,"memory_total":0}]}"#
        let event = try EngineEvent.decode(line: line)
        #expect(event == .devices(auto: 0, devices: [EngineDevice(index: 0, name: "CPU", backend: "CPU", integrated: false, memoryTotal: 0)]))
    }

    @Test func decodesInstruments() throws {
        let line = #"{"type":"instruments","instruments":[{"name":"acoustic_piano","program":0},{"name":"drums","program":128}]}"#
        let event = try EngineEvent.decode(line: line)
        #expect(event == .instruments([EngineInstrument(name: "acoustic_piano", program: 0), EngineInstrument(name: "drums", program: 128)]))
    }

    @Test func decodesLoadAndReady() throws {
        #expect(try EngineEvent.decode(line: #"{"type":"load","progress":0.42}"#) == .load(progress: 0.42))
        let ready = try EngineEvent.decode(line: #"{"type":"ready","device":{"index":0,"name":"CPU","backend":"CPU"},"chunks":3}"#)
        #expect(ready == .ready(device: EngineDevice(index: 0, name: "CPU", backend: "CPU", integrated: nil, memoryTotal: nil), chunks: 3))
    }

    @Test func decodesUpdate() throws {
        let line = #"{"type":"update","progress":0.33,"finalized_through":5.0,"notes":[{"onset":1.23,"offset":1.56,"pitch":60,"program":0,"is_drum":false,"instrument":"acoustic_piano"}]}"#
        let event = try EngineEvent.decode(line: line)
        let note = EngineNote(onset: 1.23, offset: 1.56, pitch: 60, program: 0, isDrum: false, instrument: "acoustic_piano")
        #expect(event == .update(progress: 0.33, finalizedThrough: 5.0, notes: [note]))
    }

    @Test func decodesDoneAndError() throws {
        #expect(try EngineEvent.decode(line: #"{"type":"done","note_count":812}"#) == .done(noteCount: 812))
        let error = try EngineEvent.decode(line: #"{"type":"error","code":"Cancelled","message":"cancelled by host"}"#)
        #expect(error == .error(code: "Cancelled", message: "cancelled by host"))
    }

    @Test func rejectsUnknownType() {
        #expect(throws: DecodingError.self) {
            try EngineEvent.decode(line: #"{"type":"mystery"}"#)
        }
    }

    @Test func missingHelperIsReported() {
        let empty = Bundle(path: NSTemporaryDirectory()) ?? Bundle()
        #expect(throws: EngineLocatorError.missing) {
            try EngineLocator.locate(in: empty)
        }
    }
}
