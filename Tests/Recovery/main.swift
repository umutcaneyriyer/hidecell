import Foundation
import Darwin
signal(SIGPIPE, SIG_IGN)
VisibilityGuardian.run(bundlePath: CommandLine.arguments[1])
