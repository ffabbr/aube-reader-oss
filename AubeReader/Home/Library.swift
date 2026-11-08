import UIKit
import UniformTypeIdentifiers

/// The home screen: every document as a book in a carousel standing on a timber
/// panel, with Settings and a plus in the navigation bar above it.
final class LibraryViewController: UIViewController {
  /// A document was picked: its index.
  var onOpen: ((Int) -> Void)?

  private enum Section: Hashable { case documents }

  private var collection: UICollectionView!
  private var carousel: Carousel!
  private var source: UICollectionViewDiffableDataSource<Section, Int>!
  private let panel = TimberPanel()
  private let lamp = Lamplight(frame: .zero)
  private var documents: [Document] = []
  private var laidOutFor: CGSize = .zero

  /// The bar's ink, pale over the timber.
  private static let gilt = UIColor(hex: 0xf0e2c4)

  /// Whether a dialog is up over the library.
  var presenting: Bool { presentedViewController != nil }
  /// Whether the library is on screen.
  var awake = true {
    didSet {
      guard awake != oldValue else { return }
      carousel?.awake(awake)
    }
  }

  /// The library in the navigation controller it lives in.
  func inNavigation() -> UINavigationController {
    let nav = UINavigationController(rootViewController: self)
    Parchment.dress(nav.navigationBar, script: false, ink: Self.gilt)
    nav.navigationBar.overrideUserInterfaceStyle = .dark
    return nav
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Library"
    navigationItem.largeTitleDisplayMode = .never
    view.tintColor = Self.gilt
    let add = UIBarButtonItem(
      systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.browse() })
    add.accessibilityLabel = "Import from Files"
    let gear = UIBarButtonItem(
      image: UIImage(systemName: "gearshape"), primaryAction: UIAction { [weak self] _ in self?.openSettings() })
    gear.accessibilityLabel = "Settings"
    navigationItem.leftBarButtonItem = gear
    navigationItem.rightBarButtonItem = add

    panel.frame = view.bounds
    panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // The library is always the walnut panel by lamplight, by day as by night.
    panel.overrideUserInterfaceStyle = .dark
    lamp.overrideUserInterfaceStyle = .dark
    view.addSubview(panel)

    let c = UICollectionView(frame: view.bounds, collectionViewLayout: UICollectionViewFlowLayout())
    c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    c.backgroundColor = .clear
    c.contentInsetAdjustmentBehavior = .always
    // Books respond as soon as they're touched, as buttons do outside a scroll view.
    c.delaysContentTouches = false
    c.delegate = self
    c.register(BookCell.self, forCellWithReuseIdentifier: "book")
    view.addSubview(c)
    collection = c

    carousel = Carousel(host: self, collection: c)
    c.setCollectionViewLayout(carousel.layout, animated: false)
    source = UICollectionViewDiffableDataSource(collectionView: c) { [weak self] _, path, i in
      guard let self, let d = self.documents[safe: i] else { return UICollectionViewCell() }
      let cell = self.carousel.cell(at: path, for: d)
      cell.set(d, stamp: self.stamp(for: d), current: d.id == Store.lastDocument)
      return cell
    }
    carousel.install()
    carousel.awake(awake)

    // The light in the room falls over everything, the caption too.
    lamp.frame = view.bounds
    lamp.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(lamp)

    Tilt.shared.onChange = { [weak self] in self?.relight() }
    Icons.shared.onChange = { [weak self] in self?.showIcons() }
  }

  /// Whether anything's moving, that drawing ahead should wait for.
  var busy: Bool { collection.isTracking || collection.isDragging || collection.isDecelerating }

  private func relight() {
    for case let cell as BookCell in collection.visibleCells { cell.reposition(in: collection) }
  }

  /// Everything that follows the scroll, once a book is back in its place.
  func scrolled() { carousel.scrolled() }

  /// Settings, as the gear opens them.
  func openSettings() { present(SettingsViewController.sheet(), animated: true) }

  /// Shows `documents`.
  func show(_ documents: [Document]) {
    self.documents = documents
    loadViewIfNeeded()
    var snapshot = NSDiffableDataSourceSnapshot<Section, Int>()
    if !documents.isEmpty {
      snapshot.appendSections([.documents])
      snapshot.appendItems(Array(documents.indices))
    }
    source.apply(snapshot, animatingDifferences: false)
    snapshot.reconfigureItems(snapshot.itemIdentifiers)
    source.apply(snapshot, animatingDifferences: false)
    carousel.refreshed()
  }

  /// Every document.
  var allDocuments: [Document] { documents }

  /// The document shown at `path`.
  func document(at path: IndexPath) -> Document? { documents[safe: path.item] }

  /// Brings the book of document `index` to the centre.
  func scroll(to index: Int) {
    view.layoutIfNeeded()
    collection.layoutIfNeeded()
    guard let path = source.indexPath(for: index) else { return }
    carousel.bring(path)
    collection.layoutIfNeeded()
  }

  /// Files, to pick a document from.
  private func browse() {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .plainText, .rtf], asCopy: true)
    picker.allowsMultipleSelection = true
    picker.delegate = self
    present(picker, animated: true)
  }

  // ─── Documents on their way ──────────────────────────────────────────────

  /// Shows how far along a document being brought in has got, on its book.
  func showProgress(of id: String) {
    guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
    cell(i)?.showStatus(of: id)
  }

  /// The books on show take up any drawings that have come since they were set.
  private func showIcons() {
    for case let cell as BookCell in collection.visibleCells {
      guard let path = collection.indexPath(for: cell), let d = document(at: path) else { continue }
      cell.show(stamp: stamp(for: d))
    }
    carousel.refreshed()
  }

  /// The drawing for a document, as ink. One still on its way in may yet change
  /// its title, which is what the drawing is chosen by, so it waits.
  private func stamp(for d: Document) -> UIImage? {
    d.openable ? Icons.shared.stamp(for: d.title) : nil
  }

  /// Says why a document can't be opened yet, and what can be done about it.
  func explain(_ d: Document) {
    guard let e = Imports.shared.entry(d.id) else { return }
    switch e.stage {
    case .locked: askPassword(for: d.id, again: false)
    case .failed:
      let alert = UIAlertController(title: "Couldn’t Bring In “\(e.title)”", message: e.problem, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "Try Again", style: .default) { _ in Imports.shared.retry(d.id) })
      alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in Imports.shared.remove(d.id) })
      alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
      present(alert, animated: true)
    default:
      break
    }
  }

  private func askPassword(for id: String, again: Bool) {
    let alert = UIAlertController(
      title: again ? "That Password Didn’t Work" : "This PDF Is Locked", message: "Enter its password to bring it in. An unlocked copy is kept in the app.",
      preferredStyle: .alert)
    alert.addTextField {
      $0.isSecureTextEntry = true
      $0.placeholder = "Password"
    }
    alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self, weak alert] _ in
      let word = alert?.textFields?.first?.text ?? ""
      if !Imports.shared.unlock(id, password: word) { self?.askPassword(for: id, again: true) }
    })
    alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in Imports.shared.remove(id) })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert, animated: true)
  }

  private func confirmDelete(_ id: String) {
    let name = Imports.shared.entry(id)?.title ?? "Document"
    let alert = UIAlertController(
      title: "Delete “\(name)”?", message: "Its notes and rewritten versions go with it. The original file isn’t touched.", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in Imports.shared.remove(id) })
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    present(alert, animated: true)
  }

  func open(_ index: Int) {
    onOpen?(index)
  }

  // ─── Books, for the zoom in and out ──────────────────────────────────────

  private func cell(_ index: Int) -> BookCell? {
    guard let path = source.indexPath(for: index) else { return nil }
    return collection.cellForItem(at: path) as? BookCell
  }

  /// Where the book for document `index` lies, in `view`'s coordinates. `now`,
  /// where the screen shows it at this moment: the book may still be moving.
  func sheetFrame(_ index: Int, in view: UIView, now: Bool = false) -> CGRect {
    self.view.layoutIfNeeded()
    collection.layoutIfNeeded()
    guard let sheet = cell(index)?.sheetView else { return CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) }
    if now, let shown = sheet.layer.presentation(), let screen = view.layer.presentation() {
      return shown.convert(shown.bounds, to: screen)
    }
    return sheet.convert(sheet.bounds, to: view)
  }

  /// A cover to swing open over the page.
  /// The copy travels above the library, out of its lamplight, so it takes the light along with it.
  func sheetCover(_ index: Int) -> CoverFaces? {
    guard let c = cell(index), var faces = c.cover else { return nil }
    let sheet = c.sheetView
    faces.lit = lamp.lit(faces.front, on: sheet.convert(sheet.bounds, to: lamp))
    return faces
  }

  /// Hides a book's cover while a copy of it zooms in or out.
  func hideSheet(_ index: Int, _ hidden: Bool) {
    cell(index)?.lift(hidden)
  }

  // ─── Layout ──────────────────────────────────────────────────────────────

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if laidOutFor != view.bounds.size {
      laidOutFor = view.bounds.size
      collection.collectionViewLayout.invalidateLayout()
      carousel.laidOut()
    }
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) { carousel.scrolled() }

  func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    targetContentOffset.pointee = carousel.rest(for: targetContentOffset.pointee, velocity: velocity)
  }
}

extension LibraryViewController: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let before = documents.count
    Imports.shared.add(urls)
    // Its book comes in at the end, and is brought round to show it.
    scroll(to: max(before, documents.count - 1))
  }
}

extension LibraryViewController: UICollectionViewDelegate {
  // ─── Context menu ────────────────────────────────────────────────────────

  /// Pressed and held, a book lifts and offers to open or share its document.
  func collectionView(
    _ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let path = indexPaths.first, let i = source.itemIdentifier(for: path), let d = documents[safe: i] else { return nil }
    return UIContextMenuConfiguration(identifier: i as NSNumber, previewProvider: nil) { [weak self] _ in
      let open = UIAction(title: "Open", image: UIImage(systemName: "arrow.up.forward.square")) { _ in self?.open(i) }
      let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
        self?.share(d, from: collectionView.cellForItem(at: path))
      }
      guard d.imported else {
        return UIMenu(children: [UIMenu(options: .displayInline, children: [open]), UIMenu(options: .displayInline, children: [share])])
      }
      // One brought in can be looked over again, and taken away.
      var about: [UIAction] = []
      if let e = Imports.shared.entry(d.id), e.readable {
        about.append(UIAction(title: "Check Again", image: UIImage(systemName: "arrow.clockwise")) { _ in Imports.shared.startCheck(d.id) })
      }
      let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
        self?.confirmDelete(d.id)
      }
      return UIMenu(children: [
        UIMenu(options: .displayInline, children: [open]), UIMenu(options: .displayInline, children: [share] + about),
        UIMenu(options: .displayInline, children: [delete]),
      ])
    }
  }

  func collectionView(
    _ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
    highlightPreviewForItemAt indexPath: IndexPath
  ) -> UITargetedPreview? { bookPreview(indexPath) }

  func collectionView(
    _ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
    dismissalPreviewForItemAt indexPath: IndexPath
  ) -> UITargetedPreview? { bookPreview(indexPath) }

  /// The book lifts on its own corners and its own shadow: the system's platter
  /// and shadow are left off, so there is one lift, the system's, and one shadow, the book's.
  private func bookPreview(_ path: IndexPath) -> UITargetedPreview? {
    guard let preview = (collection.cellForItem(at: path) as? BookCell)?.preview else { return nil }
    let parameters = UIPreviewParameters()
    parameters.backgroundColor = .clear
    parameters.visiblePath = preview.outline
    parameters.shadowPath = UIBezierPath()
    return UITargetedPreview(view: preview.view, parameters: parameters)
  }

  /// Hands the document to the share sheet: the file itself, if it came from one, or else its title and authors.
  private func share(_ d: Document, from cell: UIView?) {
    var items: [Any] = ["\(d.title)\n\(Face.authors(d.authors))"]
    if d.imported, let e = Imports.shared.entry(d.id) { items = [Imports.original(d.id, e.fileName)] }
    let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
    sheet.popoverPresentationController?.sourceView = cell ?? view
    present(sheet, animated: true)
  }

  // ─── Selection ───────────────────────────────────────────────────────────

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: false)
    // A book at the side comes to the centre, rather than opening.
    if carousel.tapped(indexPath) { return }
    if let i = source.itemIdentifier(for: indexPath) { open(i) }
  }
}

// ─── Type ────────────────────────────────────────────────────────────────────

/// The library's lettering: SF for the app, New York for a paper's own title.
enum Face {
  static func serif(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
    let d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    return UIFont(descriptor: d.withDesign(.serif) ?? d, size: size)
  }

  static func authors(_ names: [String]) -> String {
    names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
  }
}
