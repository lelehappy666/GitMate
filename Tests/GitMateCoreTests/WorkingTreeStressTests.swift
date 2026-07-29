import Foundation
import GitMateCore

let workingTreeStressTests = [
    TestCase("五万条状态按二百条分页且不丢失") {
        let data = WorkingTreeStressFixture.makeUntrackedData(count: 50_000)

        let batches = try WorkingTreeParser.parseUntrackedBatches(
            data,
            generation: 11,
            batchSize: 200
        )

        try expectEqual(batches.count, 250, "应生成二百五十批")
        try expect(
            batches.allSatisfy { $0.files.count <= 200 },
            "任何批次不得超过二百"
        )
        try expectEqual(
            batches.reduce(0) { $0 + $1.files.count },
            50_000,
            "不得丢失文件"
        )
        try expectEqual(
            batches.first?.files.first?.path,
            "文件-00000.swift",
            "首个文件顺序必须稳定"
        )
        try expectEqual(
            batches.last?.files.last?.path,
            "文件-49999.swift",
            "末个文件顺序必须稳定"
        )
    }
]

private enum WorkingTreeStressFixture {
    static func makeUntrackedData(count: Int) -> Data {
        var data = Data()
        data.reserveCapacity(count * 24)
        for index in 0..<count {
            let path = String(
                format: "文件-%05d.swift",
                index
            )
            data.append(Data(path.utf8))
            data.append(0)
        }
        return data
    }
}
