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
    TestCase("超长历史适配全部时降级到最新提交可见的历史概览") { @MainActor in
        let count = 200
        let commits = (0..<count).reversed().map { index in
            let hash = String(format: "full-%03d", index)
            return commitGraphCommit(
                hash: hash,
                parents: index == 0
                    ? []
                    : [String(format: "full-%03d", index - 1)],
                decorations: index == count - 1 ? ["HEAD -> main"] : []
            )
        }
        let snapshot = commitGraphSnapshot(
            commits: commits,
            headHash: "full-199"
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
            store: InMemoryCommitGraphSnapshotStore(snapshot: snapshot)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 990,
            refreshCoordinator: coordinator
        )
        _ = await viewModel.loadCachedSnapshot()
        let screenSize = GraphSize(width: 800, height: 600)

        viewModel.fitAll(in: screenSize, padding: 48)

        let latest = try required(
            viewModel.layout.node(hash: "full-199"),
            "完整快照必须包含最新提交"
        )
        let earliest = try required(
            viewModel.layout.node(hash: "full-000"),
            "完整快照必须包含初始提交"
        )
        let latestScreenY = latest.y * viewModel.viewport.scale
            + viewModel.viewport.offsetY
        let earliestScreenY = earliest.y * viewModel.viewport.scale
            + viewModel.viewport.offsetY

        try expectEqual(
            viewModel.viewport.scale,
            CommitGraphLevelOfDetail.compactThreshold,
            "全历史低于百分之五十时必须进入最新提交概览窗口"
        )
        try expect(
            abs(latestScreenY - screenSize.height * 0.42) < 0.000_001,
            "完整 oldest-first 画布降级时必须保持底部最新提交可见"
        )
        try expect(
            earliestScreenY < 0,
            "超长历史不得继续把顶部最早提交作为适配锚点"
        )
        let visible = viewModel.visibleScene(screenSize: screenSize)
        try expect(
            visible.nodes.contains { $0.id == "full-199" },
            "降级后最新提交必须进入可见查询"
        )
        try expect(
            !visible.nodes.contains { $0.id == "full-000" },
            "降级后最早提交不应伪装成当前焦点"
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
    TestCase("普通节点拖动记录唯一手动位置真值") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        await viewModel.loadOlderCommits()

        viewModel.moveNode(
            hash: "hash-c",
            by: GraphPoint(x: 18, y: -12)
        )

        try expectEqual(
            viewModel.scene.manuallyPositionedHashes,
            Set(["hash-c"]),
            "普通节点拖动后必须明确记录为手动定位"
        )

        viewModel.replaceSelection(with: ["hash-a", "hash-b"])
        _ = try viewModel.createManualGroup(title: "分组")
        viewModel.moveNode(
            hash: "hash-a",
            by: GraphPoint(x: 8, y: 4)
        )

        try expectEqual(
            viewModel.scene.manuallyPositionedHashes,
            Set(["hash-c"]),
            "Group 成员只保存相对坐标，不得产生第二份位置真值"
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
        let revisionAfterCreate = viewModel.traditionalGroupRevision
        try expectEqual(
            viewModel.traditionalGroupBadgeByHash["hash-a"]?.title,
            "旧名称",
            "创建分组必须一次建立传统布局徽标索引"
        )

        try viewModel.renameGroup(id: groupID, title: "v2 修复")
        try expect(
            viewModel.traditionalGroupRevision > revisionAfterCreate,
            "重命名必须使轻量分组版本递增"
        )
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
        try expectEqual(
            viewModel.traditionalGroupBadgeByHash["hash-c"]?.title,
            "v2 修复",
            "新成员必须进入传统布局 O(1) 徽标索引"
        )

        try viewModel.deleteGroup(id: groupID)
        try expectEqual(viewModel.scene.groups, [], "删除后不应保留分组")
        try expectEqual(
            viewModel.traditionalGroupBadgeByHash,
            [:],
            "解散分组必须清理传统布局徽标索引"
        )
        try expectEqual(
            Set(viewModel.scene.nodePositions.keys),
            Set(["hash-a", "hash-b", "hash-c"]),
            "解散分组后所有提交都应恢复为普通节点"
        )
    },
    TestCase("版本区域可创建移动缩放改色和删除") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
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
        try expectEqual(
            viewModel.visibleScene(
                screenSize: GraphSize(width: 1_200, height: 800)
            ).regions.map(\.id),
            [regionID],
            "创建区域后无需重建提交图即可立即可见"
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
        try expectEqual(
            viewModel.visibleScene(
                screenSize: GraphSize(width: 1_200, height: 800)
            ).regions.first,
            viewModel.region(id: regionID),
            "移动、缩放和改色后可见查询必须使用最新区域"
        )

        viewModel.deleteRegion(id: regionID)
        try expectEqual(viewModel.scene.regions, [], "区域应可独立删除")
        try expectEqual(
            viewModel.visibleScene(
                screenSize: GraphSize(width: 1_200, height: 800)
            ).regions,
            [],
            "删除区域后必须立即从可见索引消失"
        )
    },
    TestCase("同一帧区域拖动与缩放批次同步一次最新矩形") { @MainActor in
        let viewModel = CommitGraphViewModel(
            reader: PagedCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            pageSize: 2
        )
        await viewModel.load()
        let regionID = viewModel.createRegion(
            title: "批量区域",
            colorHex: "#27AE60",
            rect: GraphRect(x: 100, y: 120, width: 300, height: 220)
        )

        viewModel.applyPointerChanges([
            .moveRegion(
                id: regionID,
                translation: GraphPoint(x: 30, y: 20)
            ),
            .resizeRegion(
                id: regionID,
                translation: GraphPoint(x: 50, y: 40)
            )
        ])

        try expectEqual(
            viewModel.visibleScene(
                screenSize: GraphSize(width: 1_200, height: 800)
            ).regions.first?.rect,
            GraphRect(x: 130, y: 140, width: 350, height: 260),
            "pointer 批次结束后区域索引必须同步折叠后的最终矩形"
        )
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
        _ = await cachedTask.value
        try expectEqual(
            viewModel.layout.node(hash: "hash-a"),
            nil,
            "旧派生结果返回后必须被代次门禁拒绝"
        )
    },
    TestCase("刷新派生期间的全部场景编辑不会被旧副本覆盖") { @MainActor in
        let oldSnapshot = commitGraphSnapshot(
            commits: [
                commitGraphCommit(hash: "hash-c", parents: ["hash-b"]),
                commitGraphCommit(hash: "hash-b", parents: ["hash-a"]),
                commitGraphCommit(hash: "hash-a")
            ],
            headHash: "hash-c"
        )
        let newSnapshot = commitGraphSnapshot(
            commits: [
                commitGraphCommit(hash: "hash-d", parents: ["hash-c"]),
                commitGraphCommit(hash: "hash-c", parents: ["hash-b"]),
                commitGraphCommit(hash: "hash-b", parents: ["hash-a"]),
                commitGraphCommit(hash: "hash-a")
            ],
            headHash: "hash-d"
        )
        let sceneStore = InMemoryCommitGraphSceneStore()
        let deriver = SelectivelyGatedCommitGraphDeriver(
            blockedRequestID: 2
        )
        let coordinator = CommitGraphRefreshCoordinator(
            reader: StaticCommitGraphSnapshotReader(snapshot: newSnapshot),
            store: InMemoryCommitGraphSnapshotStore(snapshot: oldSnapshot)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 910,
            sceneStore: sceneStore,
            refreshCoordinator: coordinator,
            deriver: deriver
        )
        await viewModel.loadCachedSnapshot()
        let baseCountBeforeRefresh = await deriver.baseInvocationCount()
        viewModel.replaceSelection(with: ["hash-a", "hash-b"])
        let groupID = try viewModel.createManualGroup(title: "核心历史")
        viewModel.setViewMode(.canvas)

        let refreshTask = Task { @MainActor in
            await viewModel.refresh(source: .toolbar)
        }
        await deriver.waitUntilBlocked()

        viewModel.moveNode(
            hash: "hash-c",
            by: GraphPoint(x: 31, y: 17)
        )
        viewModel.moveGroup(
            id: groupID,
            by: GraphPoint(x: 44, y: -12)
        )
        viewModel.setGroupCollapsed(id: groupID, isCollapsed: true)
        viewModel.setLineStyle(.orthogonal)
        let regionID = viewModel.createRegion(
            title: "v3.0",
            colorHex: "#7B61FF",
            rect: GraphRect(x: 80, y: 90, width: 520, height: 360)
        )
        viewModel.viewport = GraphViewport(
            offsetX: 72,
            offsetY: -38,
            scale: 1.15
        )
        let editedNodePosition = viewModel.scene.nodePositions["hash-c"]
        let editedGroup = viewModel.group(id: groupID)
        let editedViewport = viewModel.viewport

        await deriver.releaseBlockedRequest()
        await refreshTask.value

        let baseCountAfterRefresh = await deriver.baseInvocationCount()
        let sceneCountAfterRefresh = await deriver.sceneInvocationCount()
        try expectEqual(
            baseCountAfterRefresh,
            baseCountBeforeRefresh + 1,
            "同一刷新中的多轮场景修订不得重复计算拓扑和双布局"
        )
        try expect(
            sceneCountAfterRefresh >= 3,
            "场景修订后应复用同一 Git base 重做轻量场景派生"
        )

        try expectEqual(
            viewModel.scene.nodePositions["hash-c"],
            editedNodePosition,
            "刷新返回时必须保留派生期间的节点拖动"
        )
        try expectEqual(
            viewModel.group(id: groupID)?.origin,
            editedGroup?.origin,
            "刷新返回时必须保留派生期间的分组拖动"
        )
        try expectEqual(
            viewModel.group(id: groupID)?.isCollapsed,
            true,
            "刷新返回时必须保留折叠状态"
        )
        try expectEqual(viewModel.scene.lineStyle, .orthogonal, "连线样式不得回退")
        try expectEqual(
            viewModel.region(id: regionID)?.title,
            "v3.0",
            "刷新返回时必须保留新增版本区域"
        )
        try expectEqual(viewModel.viewport, editedViewport, "画布视口不得回退")
        await viewModel.persistSceneImmediately()
        let persisted = try await required(
            sceneStore.load(repositoryID: 910),
            "刷新后的最新场景必须持久化"
        )
        try expectEqual(
            persisted.groups.first(where: { $0.id == groupID })?.origin,
            editedGroup?.origin,
            "持久化场景不得写回后台派生的旧分组位置"
        )
        try expectEqual(persisted.lineStyle, .orthogonal, "持久化线型不得回退")
        try expectEqual(persisted.canvasViewport, editedViewport, "持久化视口不得回退")
    },
    TestCase("场景恢复完成前与未来版本确认后都禁止写入") { @MainActor in
        let directory = commitGraphViewModelTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let sceneURL = directory.appending(path: "911.json")
        let originalData = Data(
            """
            {"schemaVersion":99,"futureState":"恢复窗口也必须保留"}
            """.utf8
        )
        try originalData.write(to: sceneURL)
        let gatedStore = GatedDelegatingSceneStore(
            base: JSONCommitGraphSceneStore(rootDirectory: directory)
        )
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 911,
            sceneStore: gatedStore,
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: InMemoryCommitGraphSnapshotStore(snapshot: snapshot)
            )
        )
        let loadTask = Task { @MainActor in
            await viewModel.loadCachedSnapshot()
        }
        await gatedStore.waitUntilLoadStarts()

        viewModel.setLineStyle(.orthogonal)
        _ = viewModel.createRegion(
            title: "恢复中编辑",
            colorHex: "#2F80ED",
            rect: GraphRect(x: 20, y: 20, width: 240, height: 160)
        )
        await viewModel.persistSceneImmediately()
        try await Task.sleep(for: .milliseconds(350))
        let restoringData = try Data(contentsOf: sceneURL)
        try expectEqual(
            restoringData,
            originalData,
            "识别场景版本之前，立即保存和延迟保存都不得写文件"
        )

        await gatedStore.releaseLoad()
        _ = await loadTask.value
        viewModel.setLineStyle(.orthogonal)
        viewModel.pan(by: GraphPoint(x: 16, y: 8))
        await viewModel.persistSceneImmediately()
        try await Task.sleep(for: .milliseconds(350))
        let finalData = try Data(contentsOf: sceneURL)
        try expectEqual(
            finalData,
            originalData,
            "确认未来 schema 后仍必须保持原文件字节不变"
        )
        let saveCount = await gatedStore.saveCount()
        try expectEqual(
            saveCount,
            0,
            "恢复中与只读未来版本状态都不得进入存储层保存"
        )
    },
    TestCase("新代次主动取消旧的大型后台派生") { @MainActor in
        let largeSnapshot = largeCommitGraphSnapshot(count: 50_000)
        let latestSnapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-latest")],
            headHash: "hash-latest"
        )
        let snapshotStore = InMemoryCommitGraphSnapshotStore(
            snapshot: largeSnapshot
        )
        let deriver = CancellationAwareCommitGraphDeriver()
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 912,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: latestSnapshot),
                store: snapshotStore
            ),
            deriver: deriver
        )
        let oldTask = Task { @MainActor in
            await viewModel.loadCachedSnapshot()
        }
        await deriver.waitUntilFirstDerivationStarts()
        try await snapshotStore.save(latestSnapshot, repositoryID: 912)

        await viewModel.loadCachedSnapshot()
        _ = await oldTask.value

        let wasFirstCancelled = await deriver.wasFirstCancelled()
        let didFirstComplete = await deriver.didFirstCompleteFullChain()
        try expect(wasFirstCancelled, "新代次必须主动取消旧派生任务")
        try expect(
            !didFirstComplete,
            "取消后的五万提交派生不得继续完成布局、投影和索引全链"
        )
        try expect(
            viewModel.layout.node(hash: "hash-latest") != nil,
            "取消旧派生后必须安装新代次的小快照"
        )
    },
    TestCase("已有结果遇到缓存缺失或损坏时保留场景并进入陈旧状态") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let followUps: [ScriptedSnapshotStore.Step] = [
            .missing,
            .failure(.corruptedSnapshot(repositoryID: 913))
        ]
        for (index, followUp) in followUps.enumerated() {
            let store = ScriptedSnapshotStore(steps: [.snapshot(snapshot), followUp])
            let viewModel = CommitGraphViewModel(
                reader: StaticCommitGraphReader(),
                repositoryURL: commitGraphRepositoryURL,
                repositoryID: Int64(913 + index),
                sceneStore: InMemoryCommitGraphSceneStore(),
                refreshCoordinator: CommitGraphRefreshCoordinator(
                    reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                    store: store
                )
            )
            await viewModel.loadCachedSnapshot()
            let layoutBefore = viewModel.layout

            await viewModel.loadCachedSnapshot()

            try expectEqual(viewModel.layout, layoutBefore, "缓存异常不得清空已有布局")
            guard case .stale = viewModel.refreshState else {
                throw TestFailure(description: "已有结果的缓存异常必须进入陈旧状态")
            }
        }
    },
    TestCase("首次缓存缺失与损坏使用不同状态语义") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let missingViewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 915,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: ScriptedSnapshotStore(steps: [.missing])
            )
        )
        await missingViewModel.loadCachedSnapshot()
        try expectEqual(missingViewModel.refreshState, .idle, "首次无缓存应保持空闲等待刷新")

        let corruptViewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 916,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: ScriptedSnapshotStore(
                    steps: [.failure(.corruptedSnapshot(repositoryID: 916))]
                )
            )
        )
        await corruptViewModel.loadCachedSnapshot()
        guard case .failed = corruptViewModel.refreshState else {
            throw TestFailure(description: "首次缓存损坏且无显示快照时必须进入失败状态")
        }
    },
    TestCase("首屏缓存不安装重绑前仓库路径的提交") { @MainActor in
        let stale = CommitGraphSnapshot(
            repositoryPath: "/previous/repository",
            fingerprint: commitGraphFingerprint(headHash: "stale-hash"),
            commitsNewestFirst: [commitGraphCommit(hash: "stale-hash")],
            expectedCommitCount: 1,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 918,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: stale),
                store: InMemoryCommitGraphSnapshotStore(snapshot: stale)
            )
        )

        let didLoad = await viewModel.loadCachedSnapshot()

        try expectEqual(didLoad, true, "路径不匹配应安全完成缓存阶段")
        try expectEqual(viewModel.layout.nodes, [], "旧路径的提交节点不得短暂安装")
        try expectEqual(viewModel.refreshState, .idle, "应继续等待当前路径刷新")
    },
    TestCase("安装阶段直接复用后台预构建的可用提交集合") { @MainActor in
        let oldSnapshot = commitGraphSnapshot(
            generationID: UUID(
                uuidString: "10000000-0000-0000-0000-000000000001"
            )!,
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let newSnapshot = commitGraphSnapshot(
            generationID: UUID(
                uuidString: "10000000-0000-0000-0000-000000000002"
            )!,
            commits: [commitGraphCommit(hash: "hash-a")],
            headHash: "hash-a"
        )
        let deriver = AvailableHashesProbeDeriver(
            overriddenInvocation: 2,
            availableHashes: []
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 917,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: newSnapshot),
                store: ScriptedSnapshotStore(
                    steps: [.snapshot(oldSnapshot), .missing]
                )
            ),
            deriver: deriver
        )
        await viewModel.loadCachedSnapshot()
        viewModel.selectForNavigation(hash: "hash-a")

        await viewModel.refresh(source: .toolbar)

        try expectEqual(
            viewModel.selectedHash,
            nil,
            "安装必须使用后台 base 提供的 Set，而不是在主线程扫描 commits 重建"
        )
    },
    TestCase("稳定呈现租约首次加载缓存且后续刷新保持幂等") { @MainActor in
        let firstSnapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-first")],
            headHash: "hash-first"
        )
        let secondSnapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-second")],
            headHash: "hash-second"
        )
        let store = CountingCommitGraphSnapshotStore(
            snapshots: [
                941: firstSnapshot,
                942: secondSnapshot
            ]
        )
        let firstViewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 941,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(
                    snapshot: firstSnapshot
                ),
                store: store
            )
        )

        // revision=1 的首次侧边栏进入仍应先命中缓存，再执行 sidebar 刷新。
        let firstLease = firstViewModel.beginInitialPresentation()
        await firstViewModel.refreshForPresentationRevision(source: .sidebar)
        let firstPresentationLoads = await store.loadCount(
            repositoryID: 941
        )
        try expectEqual(
            firstPresentationLoads,
            2,
            "首次呈现必须先读取一次缓存，再由刷新协调器读取一次"
        )
        await firstViewModel.refreshForPresentationRevision(source: .sidebar)
        let repeatedRefreshLoads = await store.loadCount(
            repositoryID: 941
        )
        try expectEqual(
            repeatedRefreshLoads,
            3,
            "同一 ViewModel 的后续刷新不得重复执行缓存首屏读取"
        )
        firstViewModel.endInitialPresentation(firstLease)

        let reappearLease = firstViewModel.beginInitialPresentation()
        await firstViewModel.refreshForPresentationRevision(source: .sidebar)
        let reappearLoads = await store.loadCount(repositoryID: 941)
        try expectEqual(
            reappearLoads,
            4,
            "缓存成功后重新呈现只执行刷新，不得再次读取首次缓存"
        )
        firstViewModel.endInitialPresentation(reappearLease)

        let secondViewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 942,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(
                    snapshot: secondSnapshot
                ),
                store: store
            )
        )
        let secondLease = secondViewModel.beginInitialPresentation()
        await secondViewModel.refreshForPresentationRevision(source: .sidebar)
        let secondRepositoryLoads = await store.loadCount(
            repositoryID: 942
        )
        try expectEqual(
            secondRepositoryLoads,
            2,
            "切换到另一仓库后必须拥有独立的首次缓存读取"
        )
        secondViewModel.endInitialPresentation(secondLease)
    },
    TestCase("稳定呈现租约中连续刷新版本取消不取消共享缓存") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-lease")],
            headHash: "hash-lease"
        )
        let store = PresentationLeaseSnapshotStore(snapshot: snapshot)
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 943,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: store
            )
        )
        let lease = viewModel.beginInitialPresentation()
        let first = Task { @MainActor in
            await viewModel.refreshForPresentationRevision(source: .sidebar)
        }
        await store.waitUntilInitialLoadStarts()
        let second = Task { @MainActor in
            await viewModel.refreshForPresentationRevision(source: .sidebar)
        }
        first.cancel()
        await Task.yield()

        let wasCancelled = await store.wasInitialLoadCancelled()
        try expect(
            !wasCancelled,
            "仍有其他呈现租约时不得取消共享缓存任务"
        )
        let loadCountDuringRevisionChanges = await store.loadCount()
        try expectEqual(
            loadCountDuringRevisionChanges,
            1,
            "连续 revision 只允许一份首次缓存读取"
        )
        await store.releaseInitialLoad()
        await first.value
        await second.value
        try expect(
            viewModel.layout.node(hash: "hash-lease") != nil,
            "保留的租约必须完成缓存安装和刷新"
        )
        viewModel.endInitialPresentation(lease)
    },
    TestCase("呈现结束取消缓存读取且下次进入可以重试") { @MainActor in
        let snapshot = commitGraphSnapshot(
            commits: [commitGraphCommit(hash: "hash-reenter")],
            headHash: "hash-reenter"
        )
        let store = PresentationLeaseSnapshotStore(snapshot: snapshot)
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 944,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: store
            )
        )
        let firstLease = viewModel.beginInitialPresentation()
        let first = Task { @MainActor in
            await viewModel.refreshForPresentationRevision(source: .sidebar)
        }
        await store.waitUntilInitialLoadStarts()
        first.cancel()
        let wasCancelledBeforePresentationEnds = await store
            .wasInitialLoadCancelled()
        try expect(
            !wasCancelledBeforePresentationEnds,
            "取消单次刷新任务不得释放页面呈现租约"
        )
        viewModel.endInitialPresentation(firstLease)
        await store.waitUntilInitialLoadCancels()
        await first.value

        let reenterLease = viewModel.beginInitialPresentation()
        await viewModel.refreshForPresentationRevision(source: .sidebar)
        try expect(
            viewModel.layout.node(hash: "hash-reenter") != nil,
            "取消后再次进入必须重新读取缓存并完成刷新"
        )
        let loadCount = await store.loadCount()
        try expectEqual(loadCount, 3, "重进必须重新读取一次缓存，再执行一次刷新")
        viewModel.endInitialPresentation(reenterLease)
    },
    TestCase("提交图快照只派生一次分支目录且视口操作不重建") { @MainActor in
        let snapshot = branchProjectionViewModelSnapshot()
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 950,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: InMemoryCommitGraphSnapshotStore()
            )
        )

        await viewModel.refresh(source: .toolbar)

        try expectEqual(
            viewModel.branchCatalog.branch(id: "local:main")?.side,
            .trunk,
            "刷新安装时必须同时建立稳定居中主干"
        )
        try expect(
            viewModel.branchBundleProjection.bundle(containing: "hash-c")
                != nil,
            "线性普通提交必须进入概览分支束"
        )
        let revision = viewModel.branchProjectionRevision

        viewModel.pan(by: GraphPoint(x: 16, y: 24))
        viewModel.zoom(
            by: 1.1,
            anchor: GraphPoint(x: 240, y: 180)
        )

        try expectEqual(
            viewModel.branchProjectionRevision,
            revision,
            "平移和缩放只能查询现有投影，不得重建完整分支目录"
        )
    },
    TestCase("搜索束内提交自动展开并允许重新折叠") { @MainActor in
        let snapshot = branchProjectionViewModelSnapshot()
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 951,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: InMemoryCommitGraphSnapshotStore()
            )
        )
        await viewModel.refresh(source: .toolbar)
        let bundleID = try required(
            viewModel.branchBundleProjection.bundle(containing: "hash-c")?.id,
            "搜索前必须存在包含目标提交的分支束"
        )

        try expect(viewModel.navigateToFirstMatch("hash-c"), "必须命中束内提交")
        try expectEqual(viewModel.selectedHash, "hash-c", "搜索必须选中真实提交")
        try expectEqual(
            viewModel.branchBundleProjection.bundle(containing: "hash-c"),
            nil,
            "搜索命中后必须临时展开分支束"
        )

        viewModel.dismissDetail()
        viewModel.clearCanvasSelection()
        viewModel.toggleBranchBundle(id: bundleID)
        try expect(
            viewModel.branchBundleProjection.bundle(containing: "hash-c")
                != nil,
            "再次切换必须恢复自动聚合"
        )
    },
    TestCase("版本区域和手动移动立即使相关分支束失效") { @MainActor in
        let snapshot = branchProjectionViewModelSnapshot()
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 953,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: InMemoryCommitGraphSnapshotStore()
            )
        )
        await viewModel.refresh(source: .toolbar)
        let position = try required(
            viewModel.scene.nodePositions["hash-c"],
            "测试提交必须具有场景位置"
        )
        let regionID = viewModel.createRegion(
            title: "v3",
            colorHex: "#2F80ED",
            rect: GraphRect(
                x: position.x - 10,
                y: position.y - 10,
                width: 20,
                height: 20
            )
        )
        try expectEqual(
            viewModel.branchBundleProjection.bundle(containing: "hash-c"),
            nil,
            "区域内提交必须立即恢复独立节点"
        )

        viewModel.deleteRegion(id: regionID)
        try expect(
            viewModel.branchBundleProjection.bundle(containing: "hash-c")
                != nil,
            "删除区域后普通连续提交可以重新聚合"
        )
        viewModel.moveNode(
            hash: "hash-c",
            by: GraphPoint(x: 20, y: 12)
        )
        try expectEqual(
            viewModel.branchBundleProjection.bundle(containing: "hash-c"),
            nil,
            "手动移动后必须立即成为强制可见锚点"
        )
    },
    TestCase("传统分支选择固定和手动节点保护写入场景") { @MainActor in
        let snapshot = branchProjectionViewModelSnapshot()
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 952,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: InMemoryCommitGraphSnapshotStore()
            )
        )
        await viewModel.refresh(source: .toolbar)

        viewModel.setTraditionalViewportWidth(980)
        viewModel.selectTraditionalBranch(id: "local:main")
        viewModel.togglePinnedTraditionalBranch(id: "local:main")
        try expectEqual(
            viewModel.scene.lastTraditionalBranchID,
            "local:main",
            "传统浮层选择必须写入最近分支偏好"
        )
        try expect(
            viewModel.scene.pinnedTraditionalBranchIDs.contains("local:main"),
            "固定分支必须持久化到仓库场景"
        )
        try expect(
            viewModel.traditionalBranchProjection.visibleBranches.contains {
                $0.id == "local:main"
            },
            "固定 HEAD 必须继续出现在传统上下文泳道"
        )

        viewModel.moveNode(
            hash: "hash-c",
            by: GraphPoint(x: 42, y: -18)
        )
        let manualPosition = viewModel.scene.nodePositions["hash-c"]
        viewModel.resetLayout()

        try expectEqual(
            viewModel.scene.nodePositions["hash-c"],
            manualPosition,
            "自动布局不得覆盖用户手动移动的普通节点"
        )
    },
    TestCase("完整刷新原子安装主干专属传统区段投影") { @MainActor in
        let commits = [
            commitGraphCommit(hash: "feature-2", parents: ["feature-1"]),
            commitGraphCommit(hash: "main-2", parents: ["main-1"]),
            commitGraphCommit(hash: "feature-1", parents: ["main-1"]),
            commitGraphCommit(hash: "main-1", parents: ["root"]),
            commitGraphCommit(hash: "root")
        ]
        let snapshot = CommitGraphSnapshot(
            repositoryPath: commitGraphRepositoryURL.standardizedFileURL.path,
            fingerprint: CommitGraphReferenceFingerprint(
                references: [
                    CommitGraphReference(
                        name: "refs/heads/main",
                        targetHash: "main-2",
                        kind: .localBranch
                    ),
                    CommitGraphReference(
                        name: "refs/heads/feature/a",
                        targetHash: "feature-2",
                        kind: .localBranch
                    )
                ],
                headName: "feature/a",
                headHash: "feature-2",
                isShallow: false
            ),
            commitsNewestFirst: commits,
            expectedCommitCount: commits.count,
            shallowBoundaryParentHashes: [],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 955,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: InMemoryCommitGraphSnapshotStore()
            )
        )

        await viewModel.refresh(source: .toolbar)

        try expectEqual(
            viewModel.traditionalSegmentProjection.lane(for: "main-1"),
            0,
            "共享祖先必须随同一快照代次安装到 main"
        )
        try expectEqual(
            viewModel.traditionalSegmentProjection.lane(for: "feature-1"),
            1,
            "功能分支独有提交必须随同一快照代次安装"
        )
        try expectEqual(
            viewModel.traditionalBranchProjection.displayLane(
                for: "local:feature/a"
            ),
            1,
            "区段投影和分支投影不得混装不同代次"
        )
    },
    TestCase("传统分割线只接受拖动结束提交的有限最终宽度") { @MainActor in
        let snapshot = branchProjectionViewModelSnapshot()
        let viewModel = CommitGraphViewModel(
            reader: StaticCommitGraphReader(),
            repositoryURL: commitGraphRepositoryURL,
            repositoryID: 954,
            sceneStore: InMemoryCommitGraphSceneStore(),
            refreshCoordinator: CommitGraphRefreshCoordinator(
                reader: StaticCommitGraphSnapshotReader(snapshot: snapshot),
                store: InMemoryCommitGraphSnapshotStore()
            )
        )
        await viewModel.refresh(source: .toolbar)

        viewModel.setTraditionalDividerWidth(372.5)
        try expectEqual(
            viewModel.scene.traditionalDividerWidth,
            372.5,
            "一次拖动结束必须只记录最终分割线宽度"
        )
        viewModel.setTraditionalDividerWidth(.nan)
        try expectEqual(
            viewModel.scene.traditionalDividerWidth,
            372.5,
            "无效 pointer 值不得污染仓库场景"
        )
        try expectEqual(
            viewModel.traditionalPublicationIndex.state(for: "hash-e"),
            .localUnpushed,
            "没有远程引用的本地提交必须在 ViewModel 中可直接查询为未推送"
        )
    }
]

private func branchProjectionViewModelSnapshot() -> CommitGraphSnapshot {
    let commits = [
        commitGraphCommit(hash: "hash-e", parents: ["hash-d"]),
        commitGraphCommit(hash: "hash-d", parents: ["hash-c"]),
        commitGraphCommit(hash: "hash-c", parents: ["hash-b"]),
        commitGraphCommit(hash: "hash-b", parents: ["hash-a"]),
        commitGraphCommit(hash: "hash-a")
    ]
    return commitGraphSnapshot(
        commits: commits,
        headHash: "hash-e"
    )
}

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
    private var baseCount = 0
    private var sceneCount = 0
    private var didReachBlockedRequest = false
    private var blockedContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    init(blockedRequestID: Int) {
        self.blockedRequestID = blockedRequestID
    }

    func deriveGitBase(
        _ request: CommitGraphGitDerivationRequest
    ) async throws -> CommitGraphGitDerivedBase {
        baseCount += 1
        return try await base.deriveGitBase(request)
    }

    func deriveScene(
        _ request: CommitGraphSceneDerivationRequest
    ) async throws -> CommitGraphSceneDerivedState {
        sceneCount += 1
        let requestID = sceneCount
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
        return try await base.deriveScene(request)
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

    func baseInvocationCount() -> Int { baseCount }

    func sceneInvocationCount() -> Int { sceneCount }
}

private actor CancellationAwareCommitGraphDeriver:
    CommitGraphViewModelDeriving
{
    private let base = DefaultCommitGraphViewModelDeriver()
    private var invocationCount = 0
    private var firstStarted = false
    private var firstCancelled = false
    private var firstCompletedFullChain = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func deriveGitBase(
        _ request: CommitGraphGitDerivationRequest
    ) async throws -> CommitGraphGitDerivedBase {
        invocationCount += 1
        let invocation = invocationCount
        if invocation == 1 {
            firstStarted = true
            for waiter in startWaiters { waiter.resume() }
            startWaiters.removeAll()
            do {
                try await Task.sleep(for: .seconds(60))
            } catch is CancellationError {
                firstCancelled = true
                throw CancellationError()
            }
        }
        let result = try await base.deriveGitBase(request)
        if invocation == 1 {
            firstCompletedFullChain = true
        }
        return result
    }

    func deriveScene(
        _ request: CommitGraphSceneDerivationRequest
    ) async throws -> CommitGraphSceneDerivedState {
        try await base.deriveScene(request)
    }

    func waitUntilFirstDerivationStarts() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func wasFirstCancelled() -> Bool { firstCancelled }

    func didFirstCompleteFullChain() -> Bool { firstCompletedFullChain }
}

private actor AvailableHashesProbeDeriver:
    CommitGraphViewModelDeriving
{
    private let base = DefaultCommitGraphViewModelDeriver()
    private let overriddenInvocation: Int
    private let availableHashes: Set<String>
    private var invocationCount = 0

    init(
        overriddenInvocation: Int,
        availableHashes: Set<String>
    ) {
        self.overriddenInvocation = overriddenInvocation
        self.availableHashes = availableHashes
    }

    func deriveGitBase(
        _ request: CommitGraphGitDerivationRequest
    ) async throws -> CommitGraphGitDerivedBase {
        invocationCount += 1
        let derived = try await base.deriveGitBase(request)
        guard invocationCount == overriddenInvocation else { return derived }
        return CommitGraphGitDerivedBase(
            integrityReport: derived.integrityReport,
            canvasLayout: derived.canvasLayout,
            traditionalLayout: derived.traditionalLayout,
            defaultPositions: derived.defaultPositions,
            availableHashes: availableHashes,
            branchCatalog: derived.branchCatalog,
            searchIndex: derived.searchIndex,
            traditionalBranchProjection:
                derived.traditionalBranchProjection,
            traditionalSegmentProjection:
                derived.traditionalSegmentProjection,
            traditionalPublicationIndex:
                derived.traditionalPublicationIndex
        )
    }

    func deriveScene(
        _ request: CommitGraphSceneDerivationRequest
    ) async throws -> CommitGraphSceneDerivedState {
        try await base.deriveScene(request)
    }
}

private actor GatedDelegatingSceneStore: CommitGraphSceneStoring {
    private let base: any CommitGraphSceneStoring
    private var loadStarted = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var saves = 0

    init(base: any CommitGraphSceneStoring) {
        self.base = base
    }

    func load(repositoryID: Int64) async throws -> CommitGraphSceneState? {
        loadStarted = true
        for waiter in loadWaiters { waiter.resume() }
        loadWaiters.removeAll()
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
        }
        return try await base.load(repositoryID: repositoryID)
    }

    func save(
        _ scene: CommitGraphSceneState,
        repositoryID: Int64
    ) async throws {
        saves += 1
        try await base.save(scene, repositoryID: repositoryID)
    }

    func waitUntilLoadStarts() async {
        guard !loadStarted else { return }
        await withCheckedContinuation { continuation in
            loadWaiters.append(continuation)
        }
    }

    func releaseLoad() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func saveCount() -> Int { saves }
}

private actor ScriptedSnapshotStore: CommitGraphSnapshotStoring {
    enum Step: Sendable {
        case snapshot(CommitGraphSnapshot)
        case missing
        case failure(CommitGraphSnapshotStoreError)
    }

    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    func load(repositoryID _: Int64) async throws -> CommitGraphSnapshot? {
        guard !steps.isEmpty else { return nil }
        switch steps.removeFirst() {
        case let .snapshot(snapshot):
            return snapshot
        case .missing:
            return nil
        case let .failure(error):
            throw error
        }
    }

    func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID _: Int64
    ) async throws {
        steps.append(.snapshot(snapshot))
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

private actor CountingCommitGraphSnapshotStore:
    CommitGraphSnapshotStoring
{
    private var snapshots: [Int64: CommitGraphSnapshot]
    private var counts: [Int64: Int] = [:]

    init(snapshots: [Int64: CommitGraphSnapshot]) {
        self.snapshots = snapshots
    }

    func load(repositoryID: Int64) async throws -> CommitGraphSnapshot? {
        counts[repositoryID, default: 0] += 1
        return snapshots[repositoryID]
    }

    func save(
        _ snapshot: CommitGraphSnapshot,
        repositoryID: Int64
    ) async throws {
        snapshots[repositoryID] = snapshot
    }

    func loadCount(repositoryID: Int64) -> Int {
        counts[repositoryID, default: 0]
    }
}

private actor PresentationLeaseSnapshotStore:
    CommitGraphSnapshotStoring
{
    private let snapshot: CommitGraphSnapshot
    private var count = 0
    private var initialLoadContinuation:
        CheckedContinuation<CommitGraphSnapshot?, Error>?
    private var initialLoadStarted = false
    private var initialLoadCancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []

    init(snapshot: CommitGraphSnapshot) {
        self.snapshot = snapshot
    }

    func load(repositoryID _: Int64) async throws -> CommitGraphSnapshot? {
        count += 1
        guard count == 1 else { return snapshot }
        initialLoadStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                initialLoadContinuation = continuation
            }
        } onCancel: {
            Task {
                await self.cancelInitialLoad()
            }
        }
    }

    func save(
        _: CommitGraphSnapshot,
        repositoryID _: Int64
    ) async throws {}

    func waitUntilInitialLoadStarts() async {
        guard !initialLoadStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseInitialLoad() {
        initialLoadContinuation?.resume(returning: snapshot)
        initialLoadContinuation = nil
    }

    func waitUntilInitialLoadCancels() async {
        guard !initialLoadCancelled else { return }
        await withCheckedContinuation { continuation in
            cancelWaiters.append(continuation)
        }
    }

    func wasInitialLoadCancelled() -> Bool {
        initialLoadCancelled
    }

    func loadCount() -> Int { count }

    private func cancelInitialLoad() {
        guard !initialLoadCancelled else { return }
        initialLoadCancelled = true
        initialLoadContinuation?.resume(throwing: CancellationError())
        initialLoadContinuation = nil
        let waiters = cancelWaiters
        cancelWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private func largeCommitGraphSnapshot(count: Int) -> CommitGraphSnapshot {
    let commits = (0..<count).reversed().map { index in
        let hash = "large-\(index)"
        return commitGraphCommit(
            hash: hash,
            parents: index == 0 ? [] : ["large-\(index - 1)"]
        )
    }
    return commitGraphSnapshot(
        commits: commits,
        headHash: "large-\(max(count - 1, 0))"
    )
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
    generationID: UUID = UUID(),
    commits: [GitCommit],
    headHash: String
) -> CommitGraphSnapshot {
    CommitGraphSnapshot(
        generationID: generationID,
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
