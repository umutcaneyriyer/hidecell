import Foundation
import Darwin
let args = CommandLine.arguments
if args.count == 5 && args[1] == "--session-recovery", let parent = Int32(args[2]) {
    SessionRecovery.run(parent: parent, executable: args[3], directory: args[4])
}
do {
    try SessionRecovery.apply(hidden: ["example.visible", "example.alreadyHidden"])
    print("READY")
    fflush(stdout)
    while true { Thread.sleep(forTimeInterval: 1) }
} catch { fputs("\(error)\n", stderr); exit(1) }
