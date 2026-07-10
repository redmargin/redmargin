import Foundation
import RedmarginCore

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// A write to a socket whose peer has gone away raises SIGPIPE, whose default
// disposition kills the process. Both the daemon and the proxy write to sockets
// that a client can close at any moment, so take the EPIPE return value instead
// and let the write paths treat it as a closed connection.
signal(SIGPIPE, SIG_IGN)

func printUsage() {
    print("""
    Usage: redmargin-server <command> [options]

    Commands:
      run       Run as a daemon (background process)
      proxy     Run as a proxy (foreground, bridges SSH to daemon)
      version   Print version information
    """)
}

guard CommandLine.arguments.count > 1 else {
    printUsage()
    exit(1)
}

let command = CommandLine.arguments[1]

// Simple argument parser
func parseArgs() -> [String: String] {
    var result = [String: String]()
    var argIndex = 2
    while argIndex < CommandLine.arguments.count {
        let key = CommandLine.arguments[argIndex]
        if key.hasPrefix("--") && argIndex + 1 < CommandLine.arguments.count {
            let value = CommandLine.arguments[argIndex + 1]
            result[String(key.dropFirst(2))] = value
            argIndex += 2
        } else if key.hasPrefix("--") {
            result[String(key.dropFirst(2))] = "true"
            argIndex += 1
        } else {
            argIndex += 1
        }
    }
    return result
}

let args = parseArgs()

switch command {
case "version":
    print("redmargin-server 1.0.0")

case "run":
    guard let pidFile = args["pid-file"],
          let stdinSocket = args["stdin-socket"],
          let stdoutSocket = args["stdout-socket"],
          let stderrSocket = args["stderr-socket"] else {
        print("Error: Missing required arguments for run mode")
        exit(1)
    }

    Daemon.start(
        pidFile: pidFile,
        stdinSocket: stdinSocket,
        stdoutSocket: stdoutSocket,
        stderrSocket: stderrSocket
    )

case "proxy":
    let reconnect = args["reconnect"] == "true"
    Proxy.start(reconnect: reconnect)

default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}
