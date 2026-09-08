pragma Singleton
import QtQuick

// The one thing `shell/FileStore.qml` asks the shell for: the environment.
// Only the two variables the design's Data row is built out of are modelled,
// because they are the only two that file reads.
QtObject {
  property string home: "/home/kid"
  property string xdgDataHome: ""

  function env(name) {
    if (name === "HOME")
      return home
    if (name === "XDG_DATA_HOME")
      return xdgDataHome
    return ""
  }
}
