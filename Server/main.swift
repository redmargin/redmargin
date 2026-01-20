import Foundation
import RedmarginCore

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
    var args = [String: String]()
    var i = 2
    while i < CommandLine.arguments.count {
        let key = CommandLine.arguments[i]
        if key.hasPrefix("--") && i + 1 < CommandLine.arguments.count {
            let value = CommandLine.arguments[i+1]
            args[String(key.dropFirst(2))] = value
            i += 2
        } else if key.hasPrefix("--") {
             args[String(key.dropFirst(2))] = "true"
             i += 1
        } else {
            i += 1
        }
    }
    return args
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
