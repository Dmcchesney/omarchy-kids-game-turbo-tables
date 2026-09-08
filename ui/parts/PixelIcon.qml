import QtQuick

// A pixel-grid icon. `art` is a list of equal-length strings; every character
// other than "." is looked up in `inks` and painted as one square cell, so an
// icon is authored as a picture in the source and needs no image file.
//
// The garage draws every glyph this way rather than reaching for an icon font,
// because the shell hands down a monospace family with no guarantee of any
// symbol coverage, and a menu whose icons vanish under one theme's font is
// worse than a menu with none. Cells stay on whole pixels at any size, which
// is what keeps the edges hard at 1366x768 and at 2560x1440 alike.
//
// Placeholder art: these grids are drawn by hand at icon scale and are meant
// to be replaced when real art exists.
Item {
  id: icon

  property var art: []
  property color color: "#ffffff"
  // Optional per-character colours, e.g. { "A": "#fff", "B": "#000" }.
  // Characters with no entry use `color`.
  property var inks: ({})
  property bool mirror: false

  readonly property int columns: art.length > 0 ? String(art[0]).length : 0
  readonly property int rows: art.length
  readonly property real cell: (columns > 0 && rows > 0)
                               ? Math.max(1, Math.floor(Math.min(width / columns, height / rows)))
                               : 1

  implicitWidth: columns * 8
  implicitHeight: rows * 8

  Canvas {
    id: surface
    anchors.centerIn: parent
    width: icon.cell * icon.columns
    height: icon.cell * icon.rows
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      var grid = icon.art
      for (var r = 0; r < grid.length; r++) {
        var line = String(grid[r])
        for (var c = 0; c < line.length; c++) {
          var ch = line.charAt(c)
          if (ch === "." || ch === " ")
            continue
          var ink = icon.inks && icon.inks[ch] !== undefined ? icon.inks[ch] : icon.color
          ctx.fillStyle = ink
          var x = icon.mirror ? (line.length - 1 - c) : c
          ctx.fillRect(x * icon.cell, r * icon.cell, icon.cell, icon.cell)
        }
      }
    }
  }

  onArtChanged: surface.requestPaint()
  onColorChanged: surface.requestPaint()
  onInksChanged: surface.requestPaint()
  onMirrorChanged: surface.requestPaint()
  onCellChanged: surface.requestPaint()
}
