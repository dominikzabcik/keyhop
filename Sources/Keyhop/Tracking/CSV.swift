import Foundation

enum CSV {
    /// RFC 4180 rows: quoted fields may contain commas, line breaks and doubled quotes.
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var quoted = false
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if quoted {
                if scalar == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.append(scalar)
                        i += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(scalar)
                }
            } else {
                switch scalar {
                case "\"": quoted = true
                case ",":
                    row.append(String(field))
                    field = String.UnicodeScalarView()
                case "\n":
                    row.append(String(field))
                    rows.append(row)
                    row = []
                    field = String.UnicodeScalarView()
                case "\r": break
                default: field.append(scalar)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(String(field))
            rows.append(row)
        }
        return rows
    }
}
