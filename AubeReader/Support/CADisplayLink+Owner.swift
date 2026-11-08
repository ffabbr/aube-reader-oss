import QuartzCore

extension CADisplayLink {
  /// A link on the main run loop that calls `frame` with `owner` on every
  /// frame, at `rate`. A link holds its target, so one left running would keep
  /// whatever it drives alive; this one holds `owner` weakly instead, and
  /// stops itself once `owner` is gone.
  static func driving<Owner: AnyObject>(
    _ owner: Owner, rate: CAFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120),
    _ frame: @escaping (Owner, CADisplayLink) -> Void
  ) -> CADisplayLink {
    let target = FrameTarget { [weak owner] link in
      guard let owner else { return link.invalidate() }
      frame(owner, link)
    }
    let link = CADisplayLink(target: target, selector: #selector(FrameTarget.frame(_:)))
    link.preferredFrameRateRange = rate
    link.add(to: .main, forMode: .common)
    return link
  }
}

/// What a link calls each frame, standing between the link and its owner.
private final class FrameTarget: NSObject {
  private let tick: (CADisplayLink) -> Void

  init(_ tick: @escaping (CADisplayLink) -> Void) { self.tick = tick }

  @objc func frame(_ link: CADisplayLink) { tick(link) }
}
