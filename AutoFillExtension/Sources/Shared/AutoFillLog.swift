import OSLog

/// Diagnostics for the AutoFill extension. An extension can't be attached to a debugger the way an
/// app can, so the system log is the only practical window into what it did.
///
/// **Never log at `.error` here, and never mark a value `.public`.** Both were used during initial
/// bring-up and both were wrong for shipping code: `.error` entries are persisted to disk (that's
/// what makes them survivable enough to `log collect`), and `.public` on a service identifier or a
/// URI host writes a permanent, readable record of every site the user autofilled on. That's a
/// browsing history in the system log, produced by the one app on the device that should be
/// building the least of it.
///
/// `.debug` goes to the in-memory ring buffer only and is stripped unless someone explicitly
/// enables it for this subsystem:
///
///     sudo log config --mode "level:debug" --subsystem land.temmi.vaultwarden-macos.autofill
///     log stream --level debug --predicate 'subsystem == "land.temmi.vaultwarden-macos.autofill"'
///
/// Counts and non-identifying state are fine to interpolate. Anything derived from vault contents
/// or from the requesting site must stay `.private` (the default for interpolated strings) so it
/// shows as `<private>` unless a developer has opted in on that specific machine.
enum AutoFillLog {
    static let logger = Logger(subsystem: "land.temmi.vaultwarden-macos.autofill", category: "diagnostics")
}
