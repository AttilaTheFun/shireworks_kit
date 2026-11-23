// GitHubAuth: signing in to GitHub by device flow, and keeping the tokens
// (docs/Design.md, section 5). The names and behaviour are those of the
// owner's existing GitHub client, so the two can merge:
//
// - GitHubDeviceFlow: the code to show, the polls until it is entered, and
//   renewal with the refresh token;
// - GitHubToken, and the TokenStore that keeps it (KeychainTokenStore on
//   Apple's platforms, MemoryTokenStore for tests and elsewhere);
// - GitHubCredentials: an app's sign-in, renewed before it runs out and let
//   go when GitHub refuses it;
// - GitHubRequest, GitHubAnswer and GitHubTransport: one request to GitHub's
//   API and its answer, sent over the network unless a test answers.
//
// The host gives the GitHub App's client id and, for the keychain, its own
// service name and access group: nothing here names an app.
