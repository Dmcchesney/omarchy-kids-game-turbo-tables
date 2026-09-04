pragma Singleton
import QtQuick

// The error codes `shell/FileStore.qml` compares against by name, and the
// `toString` it names them with in its own messages.
//
// Declared as a QML enum rather than as properties because that is the shape
// the real one has: `FileViewError.FileNotFound` is a value on the type and
// `FileViewError.toString(code)` is a call on the singleton. The numbers are
// the ones measured on Quickshell 0.3.1 in the Omarchy VM; only the names are
// load-bearing, since `shell/FileStore.qml` never writes a literal.
//
// `Unknown` was 0 here for two rounds. It is 1 on the build that ships
// (vm-b9fb591.md §1: "FileViewError.Unknown is 1 (0 is success), not 0"), and 0
// is success -- so a model that answered 0 for an unknown error was handing back
// the code the real one uses for the opposite outcome. Nothing in
// `shell/FileStore.qml` compares against either value, which is why nothing
// caught it, and is also why correcting it costs nothing.
QtObject {
  enum Code {
    Success = 0,
    Unknown = 1,
    FileNotFound = 2,
    PermissionDenied = 3,
    NotAFile = 4
  }

  function toString(code) {
    if (code === FileViewError.Success)
      return "Success"
    if (code === FileViewError.FileNotFound)
      return "FileNotFound"
    if (code === FileViewError.PermissionDenied)
      return "PermissionDenied"
    if (code === FileViewError.NotAFile)
      return "NotAFile"
    return "Unknown"
  }
}
