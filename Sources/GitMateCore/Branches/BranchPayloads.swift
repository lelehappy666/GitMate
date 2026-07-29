import Foundation

struct BranchPayload: Decodable {
    struct Commit: Decodable {
        let sha: String
    }

    let name: String
    let commit: Commit
    let protected: Bool

    var model: GitBranch {
        GitBranch(
            name: name,
            localSHA: nil,
            remoteSHA: commit.sha,
            remoteName: name,
            upstreamName: nil,
            isProtected: protected
        )
    }
}

struct BranchProtectionPayload: Decodable {
    struct StatusChecks: Decodable {
        let strict: Bool
        let contexts: [String]
    }

    struct EnabledValue: Decodable {
        let enabled: Bool
    }

    struct PullRequestReviews: Decodable {
        let dismissStaleReviews: Bool
        let requireCodeOwnerReviews: Bool
        let requiredApprovingReviewCount: Int

        private enum CodingKeys: String, CodingKey {
            case dismissStaleReviews = "dismiss_stale_reviews"
            case requireCodeOwnerReviews = "require_code_owner_reviews"
            case requiredApprovingReviewCount = "required_approving_review_count"
        }
    }

    let requiredStatusChecks: StatusChecks?
    let enforceAdmins: EnabledValue?
    let requiredPullRequestReviews: PullRequestReviews?
    let restrictions: GitHubJSONValue?

    private enum CodingKeys: String, CodingKey {
        case requiredStatusChecks = "required_status_checks"
        case enforceAdmins = "enforce_admins"
        case requiredPullRequestReviews = "required_pull_request_reviews"
        case restrictions
    }

    var model: BranchProtectionSummary {
        BranchProtectionSummary(
            requiredApprovingReviews:
                requiredPullRequestReviews?.requiredApprovingReviewCount ?? 0,
            requiredStatusChecks: requiredStatusChecks?.contexts ?? [],
            requiresStrictStatusChecks: requiredStatusChecks?.strict ?? false,
            dismissesStaleReviews:
                requiredPullRequestReviews?.dismissStaleReviews ?? false,
            requiresCodeOwnerReview:
                requiredPullRequestReviews?.requireCodeOwnerReviews ?? false,
            enforcesAdmins: enforceAdmins?.enabled ?? false,
            hasPushRestrictions: restrictions != nil
        )
    }
}

struct TagReleasePayload: Decodable {
    let id: Int64
    let tagName: String
    let name: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case draft
        case prerelease
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }

    var model: TagReleaseSummary {
        TagReleaseSummary(
            id: id,
            tagName: tagName,
            name: name,
            isDraft: draft,
            isPrerelease: prerelease,
            publishedAt: publishedAt,
            webURL: htmlURL
        )
    }
}
