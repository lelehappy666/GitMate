import Foundation
import GitMateCore

let commitGraphViewModelTests = [
    TestCase("画布缩放限制在安全范围") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL
        )

        viewModel.zoom(by: 10, anchor: .zero)
        try expectEqual(viewModel.viewport.scale, 2, "最大缩放必须限制为 2")

        viewModel.zoom(by: 0.01, anchor: .zero)
        try expectEqual(viewModel.viewport.scale, 0.35, "最小缩放必须限制为 0.35")
    },
    TestCase("视口模型一次应用同一显示帧的有序交互") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL
        )
        let changes: [GraphViewportChange] = [
            .zoom(
                multiplier: 1.1,
                anchor: GraphPoint(x: 120, y: 80)
            ),
            .pan(GraphPoint(x: 24, y: -16)),
            .zoom(
                multiplier: 0.9,
                anchor: GraphPoint(x: 640, y: 360)
            )
        ]
        let expected = CommitGraphViewportProjector.applying(
            changes,
            to: viewModel.viewport
        )

        viewModel.applyViewportChanges(changes)

        try expectEqual(
            viewModel.viewport,
            expected,
            "同一显示帧的交互必须按事件顺序一次应用到视口"
        )
    },
    TestCase("双击空白区域可适配全部提交内容") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        let screenSize = GraphSize(width: 600, height: 400)

        viewModel.fitAll(in: screenSize, padding: 40)

        let expectedScale = min(
            (screenSize.width - 80) / viewModel.layout.contentWidth,
            (screenSize.height - 80) / viewModel.layout.contentHeight
        )
        try expectEqual(
            viewModel.viewport,
            GraphViewport(
                offsetX: (
                    screenSize.width
                        - viewModel.layout.contentWidth * expectedScale
                ) / 2,
                offsetY: (
                    screenSize.height
                        - viewModel.layout.contentHeight * expectedScale
                ) / 2,
                scale: expectedScale
            ),
            "适配全部内容必须居中并保留指定边距"
        )
    },
    TestCase("切换节点时旧详情不得覆盖最新提交") { @MainActor in
        let reader = ControlledCommitGraphReader()
        let viewModel = CommitGraphViewModel(
            reader: reader,
            repositoryURL: commitGraphRepositoryURL
        )
        await viewModel.load()
        viewModel.viewport = GraphViewport(
            offsetX: 120,
            offsetY: -80,
            scale: 1.2
        )

        let first = Task { @MainActor in
            await viewModel.select(hash: "hash-a")
        }
        await reader.waitForSelection(hash: "hash-a")

        let second = Task { @MainActor in
            await viewModel.select(hash: "hash-b")
        }
        await reader.waitForSelection(hash: "hash-b")
        await reader.resumeSelection(hash: "hash-b")
        await second.value
        await reader.resumeSelection(hash: "hash-a")
        await first.value

        try expectEqual(
            viewModel.selectedCommit?.commit.fullHash,
            "hash-b",
            "取消后完成的旧详情不得覆盖最新节点"
        )
        try expectEqual(
            viewModel.selectedDiff?.commitHash,
            "hash-b",
            "取消后完成的旧差异不得覆盖最新节点"
        )
        try expectEqual(
            viewModel.viewport,
            GraphViewport(offsetX: 120, offsetY: -80, scale: 1.2),
            "选择提交不得重置画布视口"
        )
    },
    TestCase("提交分页去重且已有节点列保持稳定") { @MainActor in
        let reader = PagedCommitGraphReader()
        let viewModel = CommitGraphViewModel(
            reader: reader,
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )

        await viewModel.load()
        let initialColumns = Dictionary(
            uniqueKeysWithValues: viewModel.layout.nodes.map {
                ($0.hash, $0.column)
            }
        )
        await viewModel.loadOlderCommits()

        try expectEqual(
            viewModel.layout.nodes.map(\.hash),
            ["hash-a", "hash-b", "hash-c"],
            "分页必须按完整哈希去重并保持提交顺序"
        )
        try expectEqual(
            viewModel.layout.nodes.first { $0.hash == "hash-a" }?.column,
            initialColumns["hash-a"],
            "追加分页不得移动已显示节点"
        )
        try expectEqual(
            viewModel.layout.nodes.first { $0.hash == "hash-b" }?.column,
            initialColumns["hash-b"],
            "追加分页不得移动已有父节点"
        )
    },
    TestCase("差异失败时仍保留已加载的提交详情") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: FailingDiffCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL
        )
        await viewModel.load()
        viewModel.viewport = GraphViewport(
            offsetX: 48,
            offsetY: -32,
            scale: 1.1
        )

        await viewModel.select(hash: "hash-a")

        try expectEqual(
            viewModel.selectedCommit?.commit.fullHash,
            "hash-a",
            "差异读取失败不得丢弃已成功加载的提交详情"
        )
        try expectEqual(
            viewModel.selectedDiff,
            nil,
            "差异失败时不应保留无效差异"
        )
        try expectEqual(
            viewModel.errorMessage,
            "提交详情已打开，但暂时无法读取差异。",
            "应以稳定错误提示差异模块失败"
        )
        try expectEqual(
            viewModel.viewport,
            GraphViewport(offsetX: 48, offsetY: -32, scale: 1.1),
            "差异失败不得重置画布视口"
        )
    },
    TestCase("选择提交后创建分组且移动与线型切换保持固定端口") { @MainActor in
        let store = InMemoryCommitGraphSceneStore()
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 42,
            sceneStore: store,
            pageSize: 2
        )
        await viewModel.load()
        await viewModel.loadOlderCommits()

        viewModel.toggleSelection(hash: "hash-a", modifiers: [.command])
        viewModel.appendSelection(hash: "hash-b")
        try expectEqual(
            viewModel.selectedHashes,
            Set(["hash-a", "hash-b"]),
            "Command 切换和 Shift 追加必须形成多选"
        )

        let groupID = try viewModel.createManualGroup(title: "同步修复")
        let groupBefore = viewModel.scene.groups.first { $0.id == groupID }
        let anchorsBefore = viewModel.scene.boundaryPorts
        let topologyBefore = viewModel.layout

        viewModel.moveGroup(
            id: groupID,
            by: GraphPoint(x: 40, y: 20)
        )
        viewModel.setLineStyle(.orthogonal)

        let groupAfter = viewModel.scene.groups.first { $0.id == groupID }
        try expectEqual(
            groupAfter?.origin,
            groupBefore.map {
                GraphPoint(x: $0.origin.x + 40, y: $0.origin.y + 20)
            },
            "移动 Group 只能平移唯一 origin"
        )
        try expectEqual(
            groupAfter?.relativePositions,
            groupBefore?.relativePositions,
            "移动 Group 不得改写成员相对坐标"
        )
        try expectEqual(
            viewModel.scene.boundaryPorts,
            anchorsBefore,
            "移动和切换线型不得改变固定端口"
        )
        try expectEqual(
            viewModel.layout,
            topologyBefore,
            "场景交互不得重新计算 Git 拓扑"
        )
    },
    TestCase("组内节点拖动只修改成员相对坐标") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        await viewModel.loadOlderCommits()
        viewModel.appendSelection(hash: "hash-a")
        viewModel.appendSelection(hash: "hash-b")
        let groupID = try viewModel.createManualGroup(title: "本地整理")
        let before = viewModel.scene.groups.first { $0.id == groupID }!
        let anchorsBefore = viewModel.scene.boundaryPorts

        viewModel.moveNode(
            hash: "hash-a",
            by: GraphPoint(x: 12, y: -8)
        )

        let after = viewModel.scene.groups.first { $0.id == groupID }!
        try expectEqual(after.origin, before.origin, "拖动成员不得移动 Group origin")
        try expectEqual(
            after.relativePositions["hash-a"],
            before.relativePositions["hash-a"].map {
                GraphPoint(x: $0.x + 12, y: $0.y - 8)
            },
            "组内成员只保存相对坐标变化"
        )
        try expectEqual(
            viewModel.scene.boundaryPorts,
            anchorsBefore,
            "拖动节点不得重新分配 Group 端口"
        )
    },
    TestCase("分组支持重命名添加成员和安全解散") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        await viewModel.loadOlderCommits()
        viewModel.replaceSelection(with: ["hash-a", "hash-b"])
        let groupID = try viewModel.createManualGroup(title: "旧名称")

        try viewModel.renameGroup(id: groupID, title: "v2 修复")
        viewModel.replaceSelection(with: ["hash-c"])
        try viewModel.addSelectedCommits(to: groupID)

        try expectEqual(
            viewModel.group(id: groupID)?.title,
            "v2 修复",
            "重命名应立即反映在场景"
        )
        try expectEqual(
            viewModel.group(id: groupID)?.memberHashes,
            Set(["hash-a", "hash-b", "hash-c"]),
            "添加提交应与已有成员取并集"
        )

        try viewModel.deleteGroup(id: groupID)
        try expectEqual(viewModel.scene.groups, [], "删除后不应保留分组")
        try expectEqual(
            Set(viewModel.scene.nodePositions.keys),
            Set(["hash-a", "hash-b", "hash-c"]),
            "解散分组后所有提交都应恢复为普通节点"
        )
    },
    TestCase("版本区域可创建移动缩放改色和删除") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL
        )
        let initialRect = GraphRect(
            x: 100,
            y: 120,
            width: 500,
            height: 360
        )

        let regionID = viewModel.createRegion(
            title: "v2.0",
            colorHex: "#2F80ED",
            rect: initialRect
        )
        viewModel.moveRegion(
            id: regionID,
            translation: GraphPoint(x: 20, y: -10)
        )
        viewModel.resizeRegion(
            id: regionID,
            translation: GraphPoint(x: 40, y: 30)
        )
        viewModel.updateRegion(
            id: regionID,
            title: "v2.1",
            colorHex: "#7B61FF",
            rect: nil
        )

        try expectEqual(
            viewModel.region(id: regionID),
            CommitGraphRegionMarker(
                id: regionID,
                title: "v2.1",
                colorHex: "#7B61FF",
                rect: GraphRect(
                    x: 120,
                    y: 110,
                    width: 540,
                    height: 390
                )
            ),
            "区域应保存编辑后的标题、颜色和范围"
        )

        viewModel.deleteRegion(id: regionID)
        try expectEqual(viewModel.scene.regions, [], "区域应可独立删除")
    },
    TestCase("自动分组建议确认前不创建分组") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()

        await viewModel.prepareGroupSuggestions()

        try expectEqual(
            viewModel.scene.groups,
            [],
            "读取自动分组建议不得直接创建 Group"
        )
        let suggestion = try required(
            viewModel.groupSuggestions.first,
            "完整历史应产生 main 分支建议"
        )
        _ = try viewModel.confirmGroupSuggestion(id: suggestion.id)
        try expectEqual(
            viewModel.scene.groups.count,
            1,
            "仅在用户确认候选后创建 Group"
        )
        try expect(
            viewModel.scene.groups[0].memberHashes
                .isSuperset(of: ["hash-a", "hash-b", "hash-c"]),
            "确认建议应使用完整历史中的成员"
        )
    },
    TestCase("提交图恢复本地场景且保存失败不阻断交互") { @MainActor in
        let storedScene = CommitGraphSceneState(
            nodePositions: [
                "hash-a": GraphPoint(x: 720, y: 160),
                "hash-b": GraphPoint(x: 720, y: 300)
            ],
            lineStyle: .orthogonal
        )
        let store = InMemoryCommitGraphSceneStore(
            scenes: [88: storedScene],
            shouldFailSave: true
        )
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 88,
            sceneStore: store,
            pageSize: 2
        )

        await viewModel.load()
        try expectEqual(
            viewModel.scene.nodePositions["hash-a"],
            GraphPoint(x: 720, y: 160),
            "加载提交历史后必须恢复仓库专属场景"
        )
        viewModel.moveNode(
            hash: "hash-a",
            by: GraphPoint(x: 20, y: 10)
        )
        await viewModel.persistSceneImmediately()

        try expectEqual(
            viewModel.scene.nodePositions["hash-a"],
            GraphPoint(x: 740, y: 170),
            "持久化失败不得回滚本地交互"
        )
        try expectEqual(
            viewModel.sceneWarningMessage,
            "画布布局暂时无法保存。",
            "保存失败应显示非阻塞稳定提示"
        )
    },
    TestCase("同一显示帧的多次拖动只刷新一次动态路径") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        let topologyBefore = viewModel.layout
        let portsBefore = viewModel.scene.edgePorts
        let revisionBefore = viewModel.pathRevision

        viewModel.applyPointerChanges([
            .moveNode(
                hash: "hash-a",
                translation: GraphPoint(x: 5, y: 3)
            ),
            .moveNode(
                hash: "hash-a",
                translation: GraphPoint(x: 7, y: -1)
            )
        ])

        try expectEqual(
            viewModel.scene.nodePositions["hash-a"],
            viewModel.layout.node(hash: "hash-a").map {
                GraphPoint(x: $0.x + 12, y: $0.y + 2)
            },
            "同一帧内的节点增量必须按顺序折叠"
        )
        try expectEqual(
            viewModel.pathRevision,
            revisionBefore + 1,
            "同一显示帧只能发布一次路径刷新"
        )
        try expectEqual(
            viewModel.scene.edgePorts,
            portsBefore,
            "拖动批次不得重新分配普通提交端口"
        )
        try expectEqual(
            viewModel.layout,
            topologyBefore,
            "拖动批次不得重新计算 Git 拓扑"
        )
    },
    TestCase("刷新只对账 Git 变化并保留用户场景") { @MainActor in
        let groupID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!
        let region = CommitGraphRegionMarker(
            id: UUID(
                uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
            )!,
            title: "v2.0",
            colorHex: "#2F80ED",
            rect: GraphRect(x: 40, y: 80, width: 600, height: 420)
        )
        let boundaryKey = CollapsedEdgeKey(
            groupID: groupID,
            externalNodeID: "hash-c",
            direction: .enteringGroup
        )
        let boundaryPorts = CommitGraphEdgePorts(
            source: PortAnchor(side: .bottom, offset: 0.25),
            target: PortAnchor(side: .top, offset: 0.75)
        )
        let storedScene = CommitGraphSceneState(
            nodePositions: [:],
            groups: [
                CommitGraphGroup(
                    id: groupID,
                    title: "核心历史",
                    memberHashes: ["hash-a", "hash-b"],
                    source: .manual,
                    origin: GraphPoint(x: 360, y: 220),
                    relativePositions: [
                        "hash-a": GraphPoint(x: 0, y: 0),
                        "hash-b": GraphPoint(x: 0, y: 126)
                    ],
                    isCollapsed: true
                )
            ],
            regions: [region],
            boundaryPorts: [boundaryKey: boundaryPorts],
            lineStyle: .orthogonal,
            viewMode: .canvas,
            canvasViewport: GraphViewport(
                offsetX: 140,
                offsetY: -90,
                scale: 1.2
            )
        )
        let oldSnapshot = commitGraphSnapshot(
            commits: [
                commitGraphCommit(
                    hash: "hash-c",
                    parents: ["hash-b"]
                ),
                commitGraphCommit(
                    hash: "hash-b",
                    parents: ["hash-a"]
                ),
                commitGraphCommit(hash: "hash-a")
            ],
            headHash: "hash-c"
        )
        let newSnapshot = commitGraphSnapshot(
            commits: [
                commitGraphCommit(
                    hash: "hash-d",
                    parents: ["hash-c"]
                ),
                commitGraphCommit(
                    hash: "hash-c",
                    parents: ["hash-b"]
                ),
                commitGraphCommit(
                    hash: "hash-b",
                    parents: ["hash-a"]
                ),
                commitGraphCommit(hash: "hash-a")
            ],
            headHash: "hash-d"
        )
        let snapshotStore = InMemoryCommitGraphSnapshotStore(
            snapshot: oldSnapshot
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: newSnapshot),
            store: snapshotStore
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 901,
            sceneStore: InMemoryCommitGraphSceneStore(
                scenes: [901: storedScene]
            ),
            refreshCoordinator: coordinator
        )

        await viewModel.loadCachedSnapshot()
        await viewModel.refresh(source: .toolbar)

        try expectEqual(
            viewModel.scene.canvasViewport,
            storedScene.canvasViewport,
            "刷新必须保留画布视口"
        )
        try expectEqual(
            viewModel.scene.regions,
            [region],
            "刷新必须保留版本区域"
        )
        try expectEqual(
            viewModel.scene.groups.first?.isCollapsed,
            true,
            "刷新必须保留分组折叠状态"
        )
        try expectEqual(
            viewModel.scene.boundaryPorts[boundaryKey],
            boundaryPorts,
            "聚合键不变时必须复用原有固定端口"
        )
        try expectEqual(
            viewModel.scene.lineStyle,
            .orthogonal,
            "刷新不得改变连线样式"
        )
        try expectEqual(
            viewModel.integrityReport?.status,
            .valid,
            "刷新后必须暴露完整性校验结果"
        )
        guard case .current = viewModel.refreshState else {
            throw TestFailure(description: "成功刷新必须进入最新状态")
        }
    },
    TestCase("双布局切换保留选中提交并恢复画布视口") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [
                commitGraphCommit(
                    hash: "hash-b",
                    parents: ["hash-a"]
                ),
                commitGraphCommit(hash: "hash-a")
            ],
            headHash: "hash-b"
        )
        let storedViewport = GraphViewport(
            offsetX: 180,
            offsetY: -120,
            scale: 1.3
        )
        let sceneStore = InMemoryCommitGraphSceneStore(
            scenes: [902: CommitGraphSceneState(
                viewMode: .canvas,
                canvasViewport: storedViewport
            )]
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
            store: InMemoryCommitGraphSnapshotStore(snapshot: snapshot)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 902,
            sceneStore: sceneStore,
            refreshCoordinator: coordinator
        )
        await viewModel.loadCachedSnapshot()
        viewModel.selectForNavigation(hash: "hash-a")

        viewModel.setViewMode(.traditional)
        try expectEqual(
            viewModel.focusedHash,
            "hash-a",
            "切换布局必须优先聚焦当前选中提交"
        )
        viewModel.viewport = GraphViewport(
            offsetX: 0,
            offsetY: 0,
            scale: 1
        )
        viewModel.setViewMode(.canvas)

        try expectEqual(
            viewModel.selectedHash,
            "hash-a",
            "选中提交必须跨布局保留"
        )
        try expectEqual(
            viewModel.viewport,
            storedViewport,
            "返回画布布局时必须恢复之前视口"
        )
        viewModel.consumeFocusedHash("hash-a")
        try expectEqual(
            viewModel.focusedHash,
            nil,
            "聚焦请求成功后必须只消费一次"
        )
    },
    TestCase("刷新失败时保留上次正确快照") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: FailingCommitGraphSnapshotReader(),
            store: InMemoryCommitGraphSnapshotStore(snapshot: snapshot)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 903,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: coordinator
        )
        await viewModel.loadCachedSnapshot()
        let layoutBefore = viewModel.layout

        await viewModel.refresh(source: .sidebar)

        try expectEqual(
            viewModel.layout,
            layoutBefore,
            "刷新失败不得替换上次正确布局"
        )
        guard case .stale(let message) = viewModel.refreshState else {
            throw TestFailure(description: "有快照的刷新失败必须进入陈旧状态")
        }
        try expect(
            message.contains("上次正确结果"),
            "陈旧状态必须说明正在显示的数据来源"
        )
    },
    TestCase("可见场景在拖动后使用持久空间索引的新位置") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
            store: InMemoryCommitGraphSnapshotStore(snapshot: snapshot)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 904,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: coordinator
        )
        await viewModel.loadCachedSnapshot()
        let before = try required(
            viewModel.visibleScene(
                screenSize: GraphSize(width: 1_000, height: 800)
            ).nodes.first?.position,
            "初始节点必须可见"
        )

        viewModel.moveNode(
            hash: "hash-a",
            by: GraphPoint(x: 24, y: 16)
        )

        try expectEqual(
            viewModel.visibleScene(
                screenSize: GraphSize(width: 1_000, height: 800)
            ).nodes.first?.position,
            GraphPoint(x: before.x + 24, y: before.y + 16),
            "拖动必须局部更新持久空间索引"
        )
    },
    TestCase("并发刷新的旧结果不得覆盖新场景") { @MainActor in
        let cached = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let reader = ControlledCommitGraphSnapshotReader(
            fingerprint: commitGraphFingerprint(headHash: "hash-new")
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: reader,
            store: InMemoryCommitGraphSnapshotStore(snapshot: cached)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 905,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: coordinator
        )
        await viewModel.loadCachedSnapshot()

        let first = Task { @MainActor in
            await viewModel.refresh(source: .toolbar)
        }
        await reader.waitForRequest(1)
        let second = Task { @MainActor in
            await viewModel.refresh(source: .sidebar)
        }
        await reader.waitForRequest(2)
        await reader.completeRequest(
            2,
            snapshot: commitGraphSnapshot(
                commits: [commitGraphCommit(hash: "hash-new")],
                headHash: "hash-new"
            )
        )
        await second.value
        await reader.completeRequest(
            1,
            snapshot: commitGraphSnapshot(
                commits: [commitGraphCommit(hash: "hash-stale")],
                headHash: "hash-stale"
            )
        )
        await first.value

        try expect(
            viewModel.layout.node(hash: "hash-new") != nil,
            "最新刷新结果必须留在页面"
        )
        try expectEqual(
            viewModel.layout.node(hash: "hash-stale"),
            nil,
            "过期请求完成后不得覆盖新布局"
        )
    },
    TestCase("自动分组建议直接使用完整快照") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [
                commitGraphCommit(
                    hash: "hash-c",
                    parents: ["hash-b"],
                    decorations: ["HEAD -> main"]
                ),
                commitGraphCommit(
                    hash: "hash-b",
                    parents: ["hash-a"],
                    decorations: []
                ),
                commitGraphCommit(
                    hash: "hash-a",
                    decorations: []
                )
            ],
            headHash: "hash-c"
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
            store: InMemoryCommitGraphSnapshotStore(snapshot: snapshot)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 906,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: coordinator
        )
        await viewModel.loadCachedSnapshot()

        await viewModel.prepareGroupSuggestions()

        try expectEqual(
            viewModel.groupSuggestions.first?.memberHashes,
            Set(["hash-a", "hash-b", "hash-c"]),
            "建议必须包含快照中的完整分支历史"
        )
        try expectEqual(
            viewModel.scene.groups,
            [],
            "自动分组仍只能生成建议并等待用户确认"
        )
    },
    TestCase("未来场景版本进入持久化保护且不覆盖原文件") { @MainActor in
        let directory = commitGraphViewModelTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let sceneURL = directory.appending(path: "907.json")
        let originalData = Data(
            """
            {
              "schemaVersion": 99,
              "futureState": "必须保留"
            }
            """.utf8
        )
        try originalData.write(to: sceneURL)
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
            store: InMemoryCommitGraphSnapshotStore(snapshot: snapshot)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 907,
            sceneStore: JSONCommitGraphSceneStore(rootDirectory: directory),
            refreshCoordinator: coordinator
        )

        await viewModel.loadCachedSnapshot()
        viewModel.setViewMode(.canvas)
        viewModel.setLineStyle(.orthogonal)
        viewModel.moveNode(
            hash: "hash-a",
            by: GraphPoint(x: 24, y: 16)
        )
        await viewModel.persistSceneImmediately()

        try expect(
            viewModel.sceneWarningMessage?.contains("较新版本") == true,
            "未来 schema 必须给出明确的只读保护提示"
        )
        let persistedData = try Data(contentsOf: sceneURL)
        try expectEqual(
            persistedData,
            originalData,
            "任何自动保存和常见状态修改都不得覆盖未来 schema"
        )
    },
    TestCase("新刷新命中已落盘快照时仍安装到当前页面") { @MainActor in
        let snapshotA = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let snapshotB = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-b")],
            headHash: "hash-b"
        )
        let snapshotStore = InMemoryCommitGraphSnapshotStore(
            snapshot: snapshotA
        )
        let deriver = SelectivelyGatedCommitGraphDeriver(
            blockedRequestID: 2
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: snapshotB),
            store: snapshotStore
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 908,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: coordinator,
            deriver: deriver
        )
        await viewModel.loadCachedSnapshot()

        let first = Task { @MainActor in
            await viewModel.refresh(source: .toolbar)
        }
        await deriver.waitUntilBlocked()
        await viewModel.refresh(source: .sidebar)

        try expect(
            viewModel.layout.node(hash: "hash-b") != nil,
            "didChange=false 仅代表磁盘未变，当前 VM 仍必须安装该快照"
        )
        await deriver.releaseBlockedRequest()
        await first.value
        try expectEqual(
            viewModel.layout.node(hash: "hash-a"),
            nil,
            "过期代次不得把旧 VM 状态写回页面"
        )
    },
    TestCase("缓存加载打断首次刷新时统一收尾加载状态") { @MainActor in
        let valid = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let invalid = CommitGraphSnapshot(
            repositoryPath: valid.repositoryPath,
            fingerprint: valid.fingerprint,
            commitsNewestFirst: valid.commitsNewestFirst,
            expectedCommitCount: 2,
            shallowBoundaryParentHashes: [],
            generatedAt: valid.generatedAt
        )
        let scenarios: [(CommitGraphSnapshot?, String)] = [
            (valid, "hit"),
            (nil, "missing"),
            (invalid, "invalid")
        ]

        for (index, scenario) in scenarios.enumerated() {
            let reader = ControlledCommitGraphSnapshotReader(
                fingerprint: commitGraphFingerprint(
                    headHash: "hash-new-\(index)"
                )
            )
            let store = InMemoryCommitGraphSnapshotStore(
                snapshot: scenario.0
            )
            let coordinator = CommitGraphRefreshCoordinator(
                reader: reader,
                store: store
            )
            let viewModel = CommitGraphViewModel(
                reader: StaticCommitGraphReader(),
                repositoryURL: commitGraphRepositoryURL,
                repositoryID: Int64(920 + index),
                sceneStore: InMemoryCommitGraphSceneStore(),
                refreshCoordinator: coordinator
            )
            let refreshTask = Task { @MainActor in
                await viewModel.refresh(source: .initial)
            }
            await reader.waitForRequest(1)
            try expect(viewModel.isLoading, "首次刷新应进入加载状态")

            await viewModel.loadCachedSnapshot()

            try expect(
                !viewModel.isLoading,
                "\(scenario.1) 缓存分支成为最新代次后必须统一收尾"
            )
            await reader.completeRequest(
                1,
                snapshot: commitGraphSnapshot(
                    commits: [
                        commitGraphCommit(hash: "hash-new-\(index)")
                    ],
                    headHash: "hash-new-\(index)"
                )
            )
            await refreshTask.value
        }
    },
    TestCase("后台派生挂起时主线程仍可响应且旧结果不安装") { @MainActor in
        let snapshotA = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let snapshotB = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-b")],
            headHash: "hash-b"
        )
        let store = InMemoryCommitGraphSnapshotStore(snapshot: snapshotA)
        let deriver = SelectivelyGatedCommitGraphDeriver(
            blockedRequestID: 1
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: snapshotB),
            store: store
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 909,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: coordinator,
            deriver: deriver
        )
        let cachedTask = Task { @MainActor in
            await viewModel.loadCachedSnapshot()
        }
        await deriver.waitUntilBlocked()

        viewModel.pan(by: GraphPoint(x: 17, y: 9))
        try expectEqual(
            viewModel.viewport,
            GraphViewport(offsetX: 17, offsetY: 9, scale: 1),
            "派生挂起时 MainActor 仍必须可处理交互"
        )
        try await store.save(snapshotB, repositoryID: 909)
        await viewModel.refresh(source: .toolbar)
        try expect(
            viewModel.layout.node(hash: "hash-b") != nil,
            "较新代次必须在旧派生仍挂起时原子安装"
        )

        await deriver.releaseBlockedRequest()
        await cachedTask.value
        try expectEqual(
            viewModel.layout.node(hash: "hash-a"),
            nil,
            "旧派生结果返回后必须被代次门禁拒绝"
        )
    }
]

private let commitGraphRepositoryURL = URL(
    fileURLWithPath: "/tmp/GitMateCommitGraph"
)

private protocol CommitGraphTestReading: LocalGitReading {}

private extension CommitGraphTestReading {
    func status(repositoryURL _: URL) async throws -> LocalRepositoryStatus {
        LocalRepositoryStatus(
            branch: "main",
            upstream: "origin/main",
            ahead: 0,
            behind: 0,
            stagedCount: 0,
            unstagedCount: 0,
            untrackedCount: 0,
            conflictCount: 0
        )
    }

    func tree(
        repositoryURL _: URL,
        revision _: String,
        path _: String
    ) async throws -> [GitFileEntry] {
        []
    }

    func file(
        repositoryURL _: URL,
        revision _: String,
        path: String
    ) async throws -> GitFileContent {
        throw LocalGitReaderError.invalidPath(path)
    }

    func commits(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> GitCommitPage {
        GitCommitPage(commits: [], nextCursor: nil)
    }

    func commit(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        commitGraphDetail(hash: hash)
    }

    func diff(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitDiff {
        commitGraphDiff(hash: hash)
    }
}

private actor StaticCommitGraphReader: CommitGraphTestReading {
    func graph(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(commits: [], nextCursor: nil)
    }
}

private actor ControlledCommitGraphReader: CommitGraphTestReading {
    private var detailContinuations: [
        String: CheckedContinuation<GitCommitDetail, Error>
    ] = [:]
    private var diffContinuations: [
        String: CheckedContinuation<GitDiff, Error>
    ] = [:]

    func graph(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(
            commits: [
                commitGraphCommit(hash: "hash-a"),
                commitGraphCommit(hash: "hash-b")
            ],
            nextCursor: nil
        )
    }

    func commit(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitCommitDetail {
        try await withCheckedThrowingContinuation { continuation in
            detailContinuations[hash] = continuation
        }
    }

    func diff(
        repositoryURL _: URL,
        hash: String
    ) async throws -> GitDiff {
        try await withCheckedThrowingContinuation { continuation in
            diffContinuations[hash] = continuation
        }
    }

    func waitForSelection(hash: String) async {
        while detailContinuations[hash] == nil
            || diffContinuations[hash] == nil {
            await Task.yield()
        }
    }

    func resumeSelection(hash: String) {
        detailContinuations.removeValue(forKey: hash)?.resume(
            returning: commitGraphDetail(hash: hash)
        )
        diffContinuations.removeValue(forKey: hash)?.resume(
            returning: commitGraphDiff(hash: hash)
        )
    }
}

private actor PagedCommitGraphReader: CommitGraphTestReading {
    func graph(
        repositoryURL _: URL,
        cursor: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        if cursor == nil {
            return CommitGraphPage(
                commits: [
                    commitGraphCommit(
                        hash: "hash-a",
                        parents: ["hash-b"]
                    ),
                    commitGraphCommit(
                        hash: "hash-b",
                        parents: ["hash-c"]
                    )
                ],
                nextCursor: "2"
            )
        }
        return CommitGraphPage(
            commits: [
                commitGraphCommit(
                    hash: "hash-b",
                    parents: ["hash-c"]
                ),
                commitGraphCommit(hash: "hash-c")
            ],
            nextCursor: nil
        )
    }
}

private actor FailingDiffCommitGraphReader: CommitGraphTestReading {
    func graph(
        repositoryURL _: URL,
        cursor _: String?,
        limit _: Int
    ) async throws -> CommitGraphPage {
        CommitGraphPage(
            commits: [commitGraphCommit(hash: "hash-a")],
            nextCursor: nil
        )
    }

    func diff(
        repositoryURL _: URL,
        hash _: String
    ) async throws -> GitDiff {
        throw LocalGitReaderError.invalidRevision("差异不可用")
    }
}

private actor StaticCommitGraphSnapshotReader: CommitGraphSnapshotReading {
    private let value: CommitGraphSnapshot

    init(snapshot: CommitGraphSnapshot) {
        value = snapshot
    }

    func fingerprint(
        repositoryURL _: URL
    ) async throws -> CommitGraphReferenceFingerprint {
        value.fingerprint
    }

    func snapshot(
        repositoryURL _: URL,
        fingerprint _: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot {
        value
    }
}

private actor FailingCommitGraphSnapshotReader: CommitGraphSnapshotReading {
    func fingerprint(
        repositoryURL _: URL
    ) async throws -> CommitGraphReferenceFingerprint {
        throw LocalGitReaderError.invalidRevision("仓库不可用")
    }

    func snapshot(
        repositoryURL _: URL,
        fingerprint _: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot {
        throw LocalGitReaderError.invalidRevision("仓库不可用")
    }
}

private actor ControlledCommitGraphSnapshotReader:
    CommitGraphSnapshotReading
{
    private let value: CommitGraphReferenceFingerprint
    private var requestCount = 0
    private var requests: [
        Int: CheckedContinuation<CommitGraphSnapshot, Error>
    ] = [:]
    private var requestWaiters: [
        Int: [CheckedContinuation<Void, Never>]
    ] = [:]

    init(fingerprint: CommitGraphReferenceFingerprint) {
        value = fingerprint
    }

    func fingerprint(
        repositoryURL _: URL
    ) async throws -> CommitGraphReferenceFingerprint {
        value
    }

    func snapshot(
        repositoryURL _: URL,
        fingerprint _: CommitGraphReferenceFingerprint
    ) async throws -> CommitGraphSnapshot {
        requestCount += 1
        let requestID = requestCount
        if let waiters = requestWaiters.removeValue(forKey: requestID) {
            for waiter in waiters {
                waiter.resume()
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            requests[requestID] = continuation
        }
    }

    func waitForRequest(_ requestID: Int) async {
        guard requestCount < requestID else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[requestID, default: []].append(continuation)
        }
    }

    func completeRequest(
        _ requestID: Int,
        snapshot: CommitGraphSnapshot
    ) {
        requests.removeValue(forKey: requestID)?.resume(
            returning: snapshot
        )
    }
}

private actor SelectivelyGatedCommitGraphDeriver:
    CommitGraphViewModelDeriving
{
    private let blockedRequestID: Int
    private let base = DefaultCommitGraphViewModelDeriver()
    private var requestCount = 0
    private var didReachBlockedRequest = false
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    init(blockedRequestID: Int) {
        self.blockedRequestID = blockedRequestID
    }

    func derive(
        _ request: CommitGraphViewModelDerivationRequest
    ) async -> CommitGraphViewModelDerivedState {
        requestCount += 1
        let requestID = requestCount
        if requestID == blockedRequestID {
            await withCheckedContinuation { continuation in
                blockedContinuation = continuation
                didReachBlockedRequest = true
                for waiter in blockedWaiters {
                    waiter.resume()
                }
                blockedWaiters.removeAll()
            }
        }
        return await base.derive(request)
    }

    func waitUntilBlocked() async {
        guard !didReachBlockedRequest else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseBlockedRequest() {
        blockedContinuation?.resume()
        blockedContinuation = nil
    }
}

private actor InMemoryCommitGraphSnapshotStore:
    CommitGraphSnapshotStoring
{
    private var value: CommitGraphSnapshot?

    init(snapshot: CommitGraphSnapshot? = nil) {
        value = snapshot
    }

    func load(repositoryID _: Int64) async throws -> CommitGraphSnapshot? {
        value
    }

    func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID _: Int64
    ) async throws {
        value = snapshot
    }
}

private func commitGraphCommit(
    hash: String,
    parents: [String] = [],
    decorations: [String]? = nil
) -> GitCommit {
    GitCommit(
        shortHash: String(hash.prefix(7)),
        fullHash: hash,
        subject: "提交 \(hash)",
        authorName: "Lele",
        authorEmail: "lele@example.com",
        authoredAt: Date(timeIntervalSince1970: 100),
        parentHashes: parents,
        decorations: decorations
            ?? (hash == "hash-a" ? ["HEAD -> main"] : [])
    )
}

private func commitGraphSnapshot(
    commits: [GitCommit],
    headHash: String
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        repositoryPath: commitGraphRepositoryURL.standardizedFileURL.path,
        fingerprint: commitGraphFingerprint(headHash: headHash),
        commitsNewestFirst: commits,
        expectedCommitCount: commits.count,
        shallowBoundaryParentHashes: [],
        generatedAt: Date(timeIntervalSince1970: 1_000)
    )
}

private func commitGraphFingerprint(
    headHash: String
) -> CommitGraphReferenceFingerprint {
    CommitGraphReferenceFingerprint(
        references: [
            CommitGraphReference(
                name: "refs/heads/main",
                targetHash: headHash,
                kind: .localBranch
            )
        ],
        headName: "main",
        headHash: headHash,
        isShallow: false
    )
}

private func commitGraphDetail(hash: String) -> GitCommitDetail {
    GitCommitDetail(
        commit: commitGraphCommit(hash: hash),
        message: "完整说明 \(hash)",
        signatureStatus: .verified,
        signer: "Lele"
    )
}

private func commitGraphDiff(hash: String) -> GitDiff {
    GitDiff(
        commitHash: hash,
        files: [
            GitChangedFile(
                path: "Sources/Sync.swift",
                additions: 8,
                deletions: 2,
                isBinary: false
            )
        ],
        patch: "diff --git a/Sync.swift b/Sync.swift",
        additions: 8,
        deletions: 2
    )
}

private actor InMemoryCommitGraphSceneStore: CommitGraphSceneStoring {
    enum Failure: Error {
        case save
    }

    private var scenes: [Int64: CommitGraphSceneState]
    private let shouldFailSave: Bool

    init(
        scenes: [Int64: CommitGraphSceneState] = [:],
        shouldFailSave: Bool = false
    ) {
        self.scenes = scenes
        self.shouldFailSave = shouldFailSave
    }

    func load(repositoryID: Int64) async throws -> CommitGraphSceneState? {
        scenes[repositoryID]
    }

    func save(
        _ scene: CommitGraphSceneState,
        repositoryID: Int64
    ) async throws {
        guard !shouldFailSave else { throw Failure.save }
        scenes[repositoryID] = scene
    }
}

private func required<T>(
    _ value: T?,
    _ message: String
) throws -> T {
    guard let value else {
        throw TestFailure(description: message)
    }
    return value
}

private func commitGraphViewModelTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(
            path: "GitMateCommitGraphViewModelTests",
            directoryHint: .isDirectory
        )
        .appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
}
