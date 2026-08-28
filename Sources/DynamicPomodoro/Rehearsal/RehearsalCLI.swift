import Foundation

/// Command-line front door to the rehearsal.
///
///     swift run rehearse [canonical|meetings|restless|all] [--seed N] [--quiet]
///
/// (on macOS: `swift run DynamicPomodoro rehearse …` — the app is the only
/// executable product there so plain `swift run` keeps launching the app).
///
/// Prints the day's transcript — everything the user would have seen — and
/// every invariant finding. Exit 0 means a clean day; 2 means findings; 64
/// means the arguments made no sense. `all` runs both scripted days plus a
/// sweep of seeded restless days and prints transcripts only for failures.
public enum RehearsalCLI {
    public static func run(arguments: [String]) -> Int32 {
        var scriptName = "canonical"
        var seed: UInt64 = 1
        var quiet = false

        var it = arguments.makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--seed":
                guard let raw = it.next(), let value = UInt64(raw) else {
                    return usage("--seed needs a number")
                }
                seed = value
            case "--quiet":
                quiet = true
            case "canonical", "meetings", "restless", "all":
                scriptName = arg
            case "--help", "-h":
                return usage(nil)
            default:
                return usage("unknown argument: \(arg)")
            }
        }

        if scriptName == "all" {
            return runSweep(quiet: quiet)
        }

        let script: RehearsalScript
        switch scriptName {
        case "canonical": script = .canonical
        case "meetings": script = .meetings
        case "restless": script = .restless(seed: seed)
        default: return usage("unknown script: \(scriptName)")
        }

        let result = DayRehearsal.run(script: script, seed: seed)
        if !quiet { print(result.renderedTranscript()) }
        if !result.findings.isEmpty {
            if quiet {
                for f in result.findings { print("✗ \(f)") }
            }
            print("\(scriptName): \(result.findings.count) finding(s) — each one is a bug the user would have met.")
            return 2
        }
        if quiet { print("\(scriptName): clean.") }
        return 0
    }

    /// The pre-ship gate: both scripted days plus twenty differently seeded
    /// restless days. Transcripts are printed only for days with findings.
    private static func runSweep(quiet: Bool) -> Int32 {
        var failures = 0
        var days: [(String, DayRehearsal.Result)] = [
            ("canonical", DayRehearsal.run(script: .canonical)),
            ("meetings", DayRehearsal.run(script: .meetings)),
        ]
        for seed in UInt64(1)...20 {
            days.append(("restless-\(seed)", DayRehearsal.run(script: .restless(seed: seed), seed: seed)))
        }
        for (name, result) in days {
            if result.findings.isEmpty {
                print("✓ \(name)")
            } else {
                failures += 1
                print("✗ \(name) — \(result.findings.count) finding(s)")
                for f in result.findings { print("    \(f)") }
                if !quiet {
                    print("")
                    print(result.renderedTranscript())
                }
            }
        }
        if failures > 0 {
            print("\(failures) day(s) with findings — each finding is a bug the user would have met.")
            return 2
        }
        print("all days clean.")
        return 0
    }

    private static func usage(_ problem: String?) -> Int32 {
        if let problem { print("rehearse: \(problem)") }
        print("""
        usage: rehearse [canonical|meetings|restless|all] [--seed N] [--quiet]
          canonical  an ordinary day (default) — backs a golden transcript
          meetings   a call-heavy day — backs a golden transcript
          restless   a seeded-random day; vary with --seed
          all        both scripted days + a 20-seed restless sweep
        """)
        return problem == nil ? 0 : 64
    }
}
