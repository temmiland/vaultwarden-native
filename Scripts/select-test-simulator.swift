import Foundation

// Reads available devices from stdin. Auto-selection prefers a booted iPhone; --id validates
// one concrete available iOS device (including iPad) instead of bypassing runtime validation.
struct DeviceList: Decodable {
    struct Device: Decodable {
        let name: String
        let udid: String
        let isAvailable: Bool
        let state: String
    }

    let devices: [String: [Device]]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Unable to select an iOS test simulator: \(message)\n".utf8))
    exit(2)
}

let requestedID: UUID?
if CommandLine.arguments.count == 1 {
    requestedID = nil
} else if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--id",
          let id = UUID(uuidString: CommandLine.arguments[2]) {
    requestedID = id
} else {
    fail("expected no arguments or --id followed by a simulator UUID.")
}

let list: DeviceList
do {
    list = try JSONDecoder().decode(DeviceList.self, from: FileHandle.standardInput.readDataToEndOfFile())
} catch {
    fail("simctl device list is not valid JSON.")
}

let available = list.devices.filter { $0.key.contains("SimRuntime.iOS") }.flatMap(\.value)
    .filter { $0.isAvailable && UUID(uuidString: $0.udid) != nil }
if let requestedID {
    let matches = available.filter { UUID(uuidString: $0.udid) == requestedID }
    guard matches.count == 1, let selected = matches.first else {
        fail("explicit simulator ID is unavailable or ambiguous.")
    }
    print(selected.udid)
    exit(0)
}

let candidates = available.filter { $0.name.hasPrefix("iPhone") }
    .sorted {
        if ($0.state == "Booted") != ($1.state == "Booted") { return $0.state == "Booted" }
        return $0.udid < $1.udid
    }

guard let selected = candidates.first else {
    fail("no available iPhone simulator. Install an iOS Simulator runtime in Xcode or set VW_IOS_TEST_DESTINATION.")
}

print(selected.udid)
