// GitHubIssues: GitHub's issues REST API and attachment upload
// (docs/Design.md, sections 1 and 4), as the user signed in with
// GitHubAuth. The names, Codable keys and optionality are those of the
// owner's existing GitHub client, so the two can merge:
//
// - GitHubIssue, IssueComment, GitHubLabel and GitHubUser: GitHub's answers;
// - IssueChange: an edit of an issue, the parts given set, the rest left;
// - GitHubIssuesClient: an issue opened, read, edited, closed, reopened and
//   commented on, a comment edited or deleted, a repository's labels, and an
//   attachment uploaded (GitHub's own, `user-attachments`);
// - GitHubIssuesError: what GitHub refused that the host acts on (an
//   attachment not taken).
//
// Requests go through GitHubAuth's GitHubTransport (the network's, unless a
// test answers), with the host's token (GitHubCredentials.access, say).
