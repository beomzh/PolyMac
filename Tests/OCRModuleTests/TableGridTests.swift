import Testing
@testable import OCRModule

@Test func gridPlacesMergedCellTextTopLeftOnly() {
    let grid = TableGrid(cells: [
        .init(rows: 0...0, columns: 0...1, text: "이름"),
        .init(rows: 0...0, columns: 2...2, text: "내선"),
        .init(rows: 1...1, columns: 0...0, text: "김"),
        .init(rows: 1...1, columns: 1...1, text: "민준"),
        .init(rows: 1...1, columns: 2...2, text: "4021"),
        // 합친 칸이 다음 행에 한 번 더 와도 덮어쓰지 않는다
        .init(rows: 0...0, columns: 0...1, text: "중복"),
    ])
    #expect(grid.rows == [["이름", "", "내선"], ["김", "민준", "4021"]])
    #expect(grid.columnCount == 3)
}

@Test func tsvFlattensTabsAndNewlinesInsideCells() {
    let grid = TableGrid(rows: [["a\tb", "줄\n바꿈"], ["1,234", " 공백 "]])
    #expect(grid.tsv == "a b\t줄 바꿈\n1,234\t공백")
}

@Test func markdownUsesFirstRowAsHeaderAndEscapesPipes() {
    let grid = TableGrid(rows: [["품목", "합계"], ["A|B", "3"]])
    #expect(grid.markdown == "| 품목 | 합계 |\n| --- | --- |\n| A\\|B | 3 |")
}

@Test func shortRowsArePaddedAndHTMLIsEscaped() {
    let grid = TableGrid(rows: [["x", "y"], ["<b>&"]])
    #expect(grid.rows[1] == ["<b>&", ""])
    #expect(grid.html.contains("<td>&lt;b&gt;&amp;</td><td></td>"))
    #expect(!grid.html.contains("<b>"))
}

@Test func emptyGridIsEmpty() {
    #expect(TableGrid(cells: []).isEmpty)
    #expect(TableGrid(rows: [["", ""]]).isEmpty)
    #expect(TableGrid(rows: []).markdown == "")
}
