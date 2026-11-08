import UIKit

// ─── Driving the app from a script, for testing ──────────────────────────────

#if DEBUG
extension DeskViewController {
  /// Runs a script of commands, one to a line, against the real import pipeline
  /// and the real reader: `-drive path` on launch. Nothing here reaches a release build.
  func drive(_ path: String) {
    let log = path + ".log"
    FileManager.default.createFile(atPath: log, contents: nil)
    func say(_ s: String) {
      let line = "\(String(format: "%.1f", CACurrentMediaTime())) \(s)\n"
      if let h = FileHandle(forWritingAtPath: log) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        try? h.close()
      }
    }
    func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
    Task { @MainActor [weak self] in
      guard let self, let script = try? String(contentsOfFile: path, encoding: .utf8) else { return }
      await wait(1.5)
      var lastImport: String?
      for raw in script.split(separator: "\n") {
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        guard let command = parts.first, !command.hasPrefix("#") else { continue }
        let arg = parts.count > 1 ? parts[1] : ""
        say("> \(raw)")
        switch command {
        case "check": Store.checkImports = arg == "on"
        case "import":
          Structure.tracing = true
          Structure.trace = []
          lastImport = Imports.shared.add([URL(fileURLWithPath: arg)]).last
          await wait(0.5)
        case "ready", "done":
          let limit = CACurrentMediaTime() + (command == "ready" ? 300 : 900)
          while CACurrentMediaTime() < limit {
            guard let id = lastImport, let e = Imports.shared.entry(id) else { break }
            if e.stage == .failed || e.stage == .locked { say("  stage \(e.stage.rawValue): \(e.problem ?? "")"); break }
            if command == "ready" ? e.readable : e.stage == .done { break }
            await wait(0.25)
          }
          if let id = lastImport, let e = Imports.shared.entry(id) { say("  stage \(e.stage.rawValue) readable \(e.readable) report \(e.report.rawValue) title: \(e.title)") }
        case "open":
          let i = arg == "last" ? Document.all.count - 1 : (Int(arg) ?? 0)
          if !self.atHome { self.showHome(); await wait(1) }
          self.openFromHome(i)
          await wait(1.2)
        case "home":
          self.showHome()
          await wait(1.2)
        case "look":
          self.reader.setStyle(ReadingStyle(rawValue: Int(arg) ?? 0) ?? .plain)
          self.kick()
          await wait(0.8)
        case "scroll":
          let r = self.reader!
          r.anchorForScrolling()
          r.anchor.screenY -= Double(arg) ?? 0
          self.kick()
          await wait(0.9)
        case "shorter": self.act { self.nudgeZoom(1) }; await wait(1)
        case "longer": self.act { self.nudgeZoom(-1) }; await wait(1)
        case "harder": self.act { self.nudgeComplexity(1) }; await wait(1)
        case "easier": self.act { self.nudgeComplexity(-1) }; await wait(1)
        case "wait": await wait(Double(arg) ?? 1)
        case "homebook":
          self.homeController.scroll(to: Int(arg) ?? 0)
          await wait(0.5)
        case "settings":
          self.homeController.openSettings()
          await wait(1)
        case "ai":
          // Settings' AI page, over Settings.
          (self.homeController.presentedViewController as? UINavigationController)?.pushViewController(AccessSettingsViewController(), animated: false)
          await wait(1)
        case "slow":
          // Everything on screen at `arg` of its speed, to look at a transition frame by frame.
          self.view.window?.layer.speed = Float(arg) ?? 1
        case "topic":
          let xy = arg.split(separator: " ").compactMap { Double($0) }
          if xy.count == 2 { self.openTopic(at: CGPoint(x: xy[0], y: xy[1])) }
          await wait(3)
        case "closetopic":
          self.topic?.close()
          await wait(1)
        case "notes":
          // Everything found, and what small print wasn't taken for a note, for checking an import by.
          guard let doc = Imports.shared.book(self.document.id)?.doc else { break }
          let linked = doc.blocks.filter { $0.mark != nil }
          say("  notes \(linked.count) footnotes \(linked.filter { $0.role == .footnote }.count) printed \(doc.marks.count) folios \(doc.pages.reduce(0) { $0 + $1.folios.count }) pages \(doc.pages.count)")
          for b in linked {
            let host = doc.blocks.first { NoteToken.ids($0.text).contains(b.id) }
            var near = "(no mark)"
            if let t = host?.text, let r = t.range(of: NoteToken.make(b.id)) { near = String(NoteToken.strip(String(t[..<r.lowerBound])).suffix(28)) }
            say("  [\(b.mark ?? "?")] p\(b.pieces.first.map { $0.page + 1 } ?? 0) \(b.role.rawValue) pieces \(b.pieces.count) after “\(near)” (\(host?.role.rawValue ?? "-")): \(b.text.prefix(120))")
          }
          for b in doc.blocks where b.role == .note || (b.role == .minor && b.words >= 6) { say("  small \(b.role.rawValue) p\((b.pieces.first?.page ?? 0) + 1): \(b.text.prefix(90))") }
        case "snap":
          // For a real screenshot to be taken from outside, which is the only way to see glass as it is.
          say("SNAP \(arg)")
          await wait(1.4)
        case "trace":
          for line in Structure.trace { say(line) }
          Structure.trace = []
        case "tapnote":
          let marks = self.reader.marksInView().filter { $0.rect.midY > 90 && $0.rect.midY < CGFloat(self.screenHeight) - 90 }
          say("  marks in view \(marks.count)")
          if let m = marks[safe: Int(arg) ?? 0] {
            self.openNote(m)
            say("  opened \(m.note) at \(self.reader.content.convert(m.rect, to: self.view))")
          }
          await wait(1.2)
        case "tapat":
          // As a finger on the page would: what's under it, if anything, opens.
          let xy = arg.split(separator: " ").compactMap { Double($0) }
          if xy.count == 2 { self.tapped(CGPoint(x: xy[0], y: xy[1])) }
          say("  note open: \(self.tip?.view.note.description ?? "none")")
          await wait(1)
        case "marks":
          let r = self.reader!
          for m in r.marksInView() { say("  mark \(m.note) at \(r.content.convert(m.rect, to: self.view))") }
        case "selftest":
          // What marks do to text, with nothing to look at.
          @MainActor func check(_ name: String, _ got: String, _ want: String) { say("  \(got == want ? "ok" : "FAILED") \(name): \(got)\(got == want ? "" : " (wanted \(want))")") }
          check("strip", NoteToken.strip("a word[^12], and[^3] more"), "a word, and more")
          check("tighten", NoteToken.tighten("a word [^12], and  [^3] more"), "a word[^12], and[^3] more")
          check("shift", NoteToken.shift("a[^1] b[^20]", by: 5), "a[^6] b[^25]")
          check("keeps a mark that stayed", NoteToken.restore("the bees dance[^1] well.", from: "bees dance[^1] very well."), "the bees dance[^1] well.")
          check("puts back a dropped mark", NoteToken.restore("the bees dance very well.", from: "bees dance,[^1] very well."), "the bees dance[^1] very well.")
          check("after what closes the word", NoteToken.restore("they dance, in turn.", from: "Bees dance,[^7] then rest."), "they dance,[^7] in turn.")
          check("at the end if its word is gone", NoteToken.restore("something else entirely.", from: "Bees dance[^4] well."), "something else entirely.[^4]")
          check("drops an invented mark", NoteToken.restore("bees[^9] dance.", from: "bees dance."), "bees dance.")
          check("label of a number", MarkLabel.normal("¹²") ?? "nil", "12")
          check("label of an asterisk", MarkLabel.normal("∗") ?? "nil", "*")
          check("not a mark", MarkLabel.normal("st") ?? "nil", "nil")
          check("list", (MarkLabel.list("3–5") ?? []).joined(separator: " "), "3 4 5")
          check("list of a number and a symbol", (MarkLabel.list("1,∗†") ?? []).joined(separator: " "), "1 * †")
          check("words in a word", String(Scale.count("one two[^3] [^4] three")), "3")
          check("sentences past a mark", String(format: "%.1f", Scale.grade(of: "The bee flew.[^1] It came back.")), String(format: "%.1f", Scale.grade(of: "The bee flew. It came back.")))
          check("address over two lines", NoteToken.joinNote(["See https://a.org/b-", "c/d for it."], known: { _ in true }), "See https://a.org/b-c/d for it.")
          check("address that ends", NoteToken.joinNote(["See https://a.org/b", "for it."], known: { _ in true }), "See https://a.org/b for it.")
        case "closenote":
          self.closeTips()
          await wait(0.8)
        case "contents":
          // As a finger on the ring would.
          self.toggleContents()
          let rows = self.reader.contents()
          say("  current \(self.reader.currentRow(in: rows).map(String.init) ?? "none") of \(rows.count)")
          for (k, row) in rows.enumerated().prefix(60) { say("  [\(k)] \(String(repeating: "  ", count: row.depth))\(row.title) p\(row.page.map { String($0 + 1) } ?? "-")") }
          await wait(1.2)
        case "hit":
          // What a finger put down there would land on.
          let xy = arg.split(separator: " ").compactMap { Double($0) }
          if xy.count == 2 {
            let p = CGPoint(x: xy[0], y: xy[1])
            let v = self.view.hitTest(p, with: nil)
            say("  hit \(v.map { String(describing: type(of: $0)) } ?? "nothing") for the page's recognizers: \(!(v is UIControl) && !(v.map { $0.isDescendant(of: self.contents ?? UIView()) } ?? false))")
          }
        case "tips":
          say("  contents on screen \(self.view.subviews.filter { $0 is ContentsTip }.count)")
        case "pick":
          // As a finger on a row would.
          if let row = self.reader.contents()[safe: Int(arg) ?? 0] { self.go(to: row) }
          await wait(1.4)
          let r = self.reader!
          say("  y \(r.currentY) range \(r.range()) page \(r.ringSpot.page + 1) of \(r.ringSpot.of) contents open \(self.contents != nil)")
        case "text":
          // The paragraph on screen, with its marks, as the text holds it.
          let r = self.reader!
          say("  \(r.edition.texts.draft(r.hit(self.screenHeight / 2), Int(r.paras[r.hit(self.screenHeight / 2)].c.target), Int(r.paras[r.hit(self.screenHeight / 2)].z.target)).text.prefix(400))")
        case "dismiss":
          self.presentedViewController?.dismiss(animated: false)
          await wait(0.5)
        case "unlock":
          if let id = lastImport { say("  unlocked: \(Imports.shared.unlock(id, password: arg))") }
          await wait(0.5)
        case "remove":
          if let id = lastImport { Imports.shared.remove(id) }
          await wait(0.5)
        case "style":
          self.view.window?.overrideUserInterfaceStyle = arg == "dark" ? .dark : .light
          await wait(0.8)
        case "size":
          // As if the window were this size, which is as near as a script can get to rotating it in windowed mode.
          let wh = arg.split(separator: " ").compactMap { Double($0) }
          if wh.count == 2 { self.view.window?.frame = CGRect(x: 0, y: 0, width: wh[0], height: wh[1]) }
          await wait(1.2)
        case "orient":
          self.setNeedsUpdateOfSupportedInterfaceOrientations()
          self.view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: arg == "portrait" ? .portrait : .landscapeLeft)) { e in say("  orient: \(e.localizedDescription)") }
          await wait(1.5)
          say("  bounds \(self.view.bounds.size)")
        case "shot":
          guard let window = self.view.window else { break }
          let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
          try? image.pngData()?.write(to: URL(fileURLWithPath: arg))
          say("  shot \(arg)")
        case "memory":
          var info = task_vm_info_data_t()
          var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
          let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
          if kr == KERN_SUCCESS { say("  footprint \(info.phys_footprint / 1024 / 1024) MB") }
        case "state":
          let r = self.reader!
          say("  doc \(self.document.title.prefix(40)) look \(r.style.name) paragraphs \(r.paras.count) shown \(r.order.count) height \(Int(r.contentH)) y \(Int(r.currentY))")
        case "quit":
          say("bye")
          exit(0)
        default: say("  unknown")
        }
      }
      say("end of script")
    }
  }
}
#endif
