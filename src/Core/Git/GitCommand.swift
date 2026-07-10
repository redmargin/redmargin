import Foundation

/// Hardening flags for every `git` invocation Redmargin makes on its own.
///
/// Git reads configuration from the repository it is inspecting, and several
/// config keys name commands for Git to run: `core.fsmonitor`, `diff.external`,
/// and per-driver `diff.*.textconv`. Redmargin inspects a repository the moment a
/// file or folder inside it is opened, with no user action, so a repository
/// obtained from anywhere could otherwise execute code as the current user just
/// by being viewed. These options refuse the keys that do that.
enum GitCommand {

    /// Git-level options; must precede the subcommand.
    static let safetyOptions = ["-c", "core.fsmonitor=false"]

    /// `git diff` options that refuse repository-supplied filter commands.
    static let diffSafetyOptions = ["--no-ext-diff", "--no-textconv"]

    /// Prefixes `arguments` with the options that must lead the command line.
    static func arguments(_ arguments: [String]) -> [String] {
        safetyOptions + arguments
    }
}
