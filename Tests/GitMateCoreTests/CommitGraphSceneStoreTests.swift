import Foundation
import GitMateCore

let commitGraphSceneStoreTests = [
    TestCase("提交图场景按仓库保存并完整恢复") {
        let directory = commitGraphSceneStoreTemporaryDirectory()
        let store = JSONCommitGraphSceneStore(rootDirectory: directory)
        let groupID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        let key = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: "outside",
            direction: .leavingGroup
        )
        let scene = CommitGraphSceneState(
            nodePositions: ["outside": GraphPoint(x: 80, y: 120)],
            groups: [
                CommitGraphGroup(
                    id: groupID,
                    title: "同步修复",
                    memberHashes: ["a", "b"],
                    source: .manual,
                    origin: GraphPoint(x: 300, y: 240),
                    relativePositions: [
                        "a": GraphPoint(x: -40, y: 0),
                        "b": GraphPoint(x: 40, y: 120)
                    ],
                    isCollapsed: true
                )
            ],
            boundaryPorts: [
                key: CommitGraphEdgePorts(
                    source: PortAnchor(side: .right, offset: 0.25),
                    target: PortAnchor(side: .left, offset: 0.75)
                )
            ],
            lineStyle: .orthogonal,
            viewMode: .canvas,
            canvasViewport: GraphViewport(
                offsetX: 120,
                offsetY: -80,
                scale: 1.25
            )
        )

        try await store.save(scene, repositoryID: 42)
        let restored = try await store.load(repositoryID: 42)

        try expectEqual(restored, scene, "保存后必须完整恢复 Group、坐标和固定端口")
    },
    TestCase("不同仓库的提交图场景相互隔离") {
        let directory = commitGraphSceneStoreTemporaryDirectory()
        let store = JSONCommitGraphSceneStore(rootDirectory: directory)
        let first = CommitGraphSceneState(
            nodePositions: ["a": GraphPoint(x: 10, y: 20)]
        )
        let second = CommitGraphSceneState(
            nodePositions: ["b": GraphPoint(x: 30, y: 40)],
            lineStyle: .orthogonal
        )

        try await store.save(first, repositoryID: 1)
        try await store.save(second, repositoryID: 2)
        let restoredFirst = try await store.load(repositoryID: 1)
        let restoredSecond = try await store.load(repositoryID: 2)
        let missing = try await store.load(repositoryID: 3)

        try expectEqual(
            restoredFirst,
            first,
            "仓库一不得读取仓库二的场景"
        )
        try expectEqual(
            restoredSecond,
            second,
            "仓库二不得读取仓库一的场景"
        )
        try expectEqual(
            missing,
            nil,
            "不存在的仓库应返回空场景"
        )
    },
    TestCase("损坏场景返回稳定错误") {
        let directory = commitGraphSceneStoreTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("{broken".utf8).write(
            to: directory.appending(path: "7.json")
        )
        let store = JSONCommitGraphSceneStore(rootDirectory: directory)

        do {
            _ = try await store.load(repositoryID: 7)
            throw TestFailure(description: "损坏 JSON 必须抛出错误")
        } catch let error as CommitGraphSceneStoreError {
            try expectEqual(
                error,
                .corruptedScene(repositoryID: 7),
                "损坏 JSON 必须映射为稳定错误"
            )
        }
    },
    TestCase("临时文件不会被识别为仓库场景") {
        let directory = commitGraphSceneStoreTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(CommitGraphSceneState()).write(
            to: directory.appending(path: ".9.pending-\(UUID()).json")
        )
        let store = JSONCommitGraphSceneStore(rootDirectory: directory)
        let restored = try await store.load(repositoryID: 9)

        try expectEqual(
            restored,
            nil,
            "仅有临时文件时不得恢复不完整场景"
        )
    },
    TestCase("旧场景迁移到传统布局并使用默认画布视口") {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "nodePositions": {},
              "groups": [],
              "edgePorts": {},
              "boundaryPorts": [],
              "lineStyle": "curve"
            }
            """.utf8
        )

        let scene = try JSONDecoder().decode(
            CommitGraphSceneState.self,
            from: data
        )

        try expectEqual(
            scene.regions,
            [],
            "旧场景缺少区域字段时必须兼容为无区域"
        )
        try expectEqual(
            scene.schemaVersion,
            CommitGraphSceneState.currentSchemaVersion,
            "schema 1 场景必须在解码时迁移到当前版本"
        )
        try expectEqual(
            scene.viewMode,
            .traditional,
            "schema 1 场景必须默认使用传统布局"
        )
        try expectEqual(
            scene.canvasViewport,
            GraphViewport(),
            "schema 1 场景必须补全默认画布视口"
        )
    },
    TestCase("未知未来场景版本返回稳定错误") {
        let directory = commitGraphSceneStoreTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "schemaVersion": 99
            }
            """.utf8
        ).write(to: directory.appending(path: "19.json"))
        let store = JSONCommitGraphSceneStore(rootDirectory: directory)

        do {
            _ = try await store.load(repositoryID: 19)
            throw TestFailure(description: "未来 schema 必须被拒绝")
        } catch let error as CommitGraphSceneStoreError {
            try expectEqual(
                error,
                .unsupportedSchema(repositoryID: 19, schemaVersion: 99),
                "未知未来 schema 必须返回可识别的版本错误"
            )
        }
    },
    TestCase("版本区域随场景完整保存和恢复") {
        let directory = commitGraphSceneStoreTemporaryDirectory()
        let store = JSONCommitGraphSceneStore(rootDirectory: directory)
        let region = CommitGraphRegionMarker(
            id: UUID(
                uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
            )!,
            title: "v2.0",
            colorHex: "#2F80ED",
            rect: GraphRect(x: 120, y: 80, width: 640, height: 480)
        )
        let scene = CommitGraphSceneState(regions: [region])

        try await store.save(scene, repositoryID: 88)
        let restored = try await store.load(repositoryID: 88)

        try expectEqual(
            restored?.regions,
            [region],
            "区域标题、颜色和画布范围必须完整恢复"
        )
    }
]

private func commitGraphSceneStoreTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(
            path: "GitMateCommitGraphSceneTests",
            directoryHint: .isDirectory
        )
        .appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
}
