pragma Singleton
import QtQuick

// The error codes `shell/FileStore.qml` compares against by name, and the
// `toString` it names them with in its own messages.
//
// Declared as a QML enum rather than as properties because that is the shape
// the real one has: `FileViewError.FileNotFound` is a value on the type and
// `FileViewError.toString(code)` is a call on the singleton. Two of the three
// numbers are the ones `shell/FileStore.qml`'s header records as measured on
// Quickshell 0.3.1 in the Omarchy VM; only the names are load-bearing, since
// that file never writes a literal.
QtObject {
  enum Code {
    Unknown = 0,
    FileNotFound = 2,
    PermissionDenied = 3,
    NotAFile = 4
  }

  function toString(code) {
    if (code === FileViewError.FileNotFound)
      return "FileNotFound"
    if (code === FileViewError.PermissionDenied)
      return "PermissionDenied"
    if (code === FileViewError.NotAFile)
      return "NotAFile"
    return "Unknown"
  }
}
