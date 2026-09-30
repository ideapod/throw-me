import Foundation
import Observation
import RealityKit
import simd

/// Runs everything in the immersive room: the workshop where strings are made and wrapped,
/// the postbox you throw into, the table where gifts are unwrapped, and the strings hung around you.
///
/// Coordinates are immersive-space coordinates: origin on the floor beneath the wearer, -Z ahead.
@Observable
final class RoomController {
    // Observed by the SwiftUI attachments.
    private(set) var draftCount = 0
    /// Items on the string that still need something put in them.
    private(set) var emptyCount = 0
    private(set) var hasOutgoingBox = false
    /// The wrapped gift is being held over the postbox — letting go will post it.
    private(set) var isOverPostbox = false
    /// A gift tag for the chosen contact is sitting in the palette, ready to tie on.
    private(set) var tagWaiting = false
    /// The wrapped gift has a tag on it, so it can be posted.
    private(set) var giftAddressed = false
    /// Briefly true after trying to post a gift with no tag, so the labels can say why.
    private(set) var needsTagNudge = false
    private(set) var isUnwrapping = false

    @ObservationIgnored let root = Entity()
    @ObservationIgnored let animator = Animator()
    @ObservationIgnored var updateSubscription: EventSubscription?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let workshop = Entity()
    @ObservationIgnored private var bench: HangingStringEntity!
    @ObservationIgnored private let palette = Entity()
    @ObservationIgnored private var paletteBoard: Entity?
    @ObservationIgnored private var paletteItems: [ItemKind: StringItemEntity] = [:]
    @ObservationIgnored private var paletteSlots: [ItemKind: SIMD3<Float>] = [:]
    @ObservationIgnored private var tagSlot: SIMD3<Float>?
    @ObservationIgnored private var paletteTag: GiftTagEntity?
    @ObservationIgnored private var pendingRecipient: Person?
    @ObservationIgnored private var postbox: PostboxEntity!
    @ObservationIgnored private let tableSurface = Entity()
    @ObservationIgnored private var outgoing: (box: GiftBoxEntity, string: LoveString)?
    @ObservationIgnored private var incoming: (box: GiftBoxEntity, string: LoveString)?
    @ObservationIgnored private var hungEntities: [UUID: HangingStringEntity] = [:]
    @ObservationIgnored private var hint: Entity?
    @ObservationIgnored private let head = HeadTracker()
    @ObservationIgnored private var drag: DragState?
    @ObservationIgnored private var gaze = GazeState()
    @ObservationIgnored private var isSetUp = false
    @ObservationIgnored private var windowOpen = false
    @ObservationIgnored private var workshopPlaced = false
    @ObservationIgnored private var wasMaking = false

    // Workshop layout, relative to the wearer's eyes when the workshop opens.
    private static let benchCentre: SIMD3<Float> = [0, -0.1, -0.85]
    private static let paletteCentre: SIMD3<Float> = [0, -0.25, -0.7]
    /// Where a wrapped gift waits: off to the right, clear of the palette's hint text.
    private static let outgoingRest: SIMD3<Float> = [0.5, -0.24, -0.72]
    /// Items sit a little smaller in the palette wells than on the string.
    private static let paletteScale: Float = 0.62
    private static let defaultPostbox: SIMD3<Float> = [0.85, 0, -1.5]

    // MARK: Setup

    func setUp(model: AppModel) {
        guard !isSetUp else { return }
        isSetUp = true
        self.model = model

        root.addChild(workshop)
        bench = HangingStringEntity(items: [], span: 0.9, movable: false)
        bench.root.position = Self.benchCentre
        workshop.addChild(bench.root)

        // The palette tilts up towards you like a tray on a desk.
        palette.position = Self.paletteCentre
        palette.orientation = simd_quatf(angle: -0.45, axis: [1, 0, 0])
        workshop.addChild(palette)

        postbox = PostboxEntity()
        placePostbox(at: model.postboxPosition ?? Self.defaultPostbox)
        root.addChild(postbox.root)

        buildTable()
        #if DEBUG
        if UserDefaults.standard.string(forKey: "demo") == "postboxes" { buildPostboxLineUp() }
        if UserDefaults.standard.string(forKey: "demo") == "string" { buildDemoString() }
        #endif
        sync()
        if windowOpen { setWindowOpen(true) }
    }

    #if DEBUG
    /// `-demo string`: a filled string including a real imported photo, to check media and order.
    private func buildDemoString() {
        var photo = StringItem.empty(.photo)
        photo.media = try? MediaStore.importImage(from: URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic"))
        var note = StringItem.empty(.note)
        note.text = "1 · 2 · 3 · 4"
        let items = [StringItem.random(.sound), photo, note, StringItem.random(.photo)]
        for (i, item) in items.enumerated() {
            let e = StringItemEntity(item: item)
            bench.root.addChild(e.root)
            // Drop each one further right than the last: they should end up in this order.
            bench.insert(e, atWorld: bench.root.convert(position: [Float(i) * 0.3 - 0.4, 0, 0], to: nil), eye: nil, animator: animator)
        }
        updateCounts()
    }

    /// `-demo postboxes`: every Vision Pro country's postbox in two staggered arcs, labelled.
    private func buildPostboxLineUp() {
        postbox.root.isEnabled = false
        let regions = PostboxStyle.visionProRegions
        for (i, region) in regions.enumerated() {
            let front = i < 7
            let index = Float(front ? i : i - 7)
            let count = Float(front ? 7 : regions.count - 7)
            let radius: Float = front ? 4.2 : 6.2
            let angle = (index - (count - 1) / 2) * (front ? 0.17 : 0.13)
            let spot = SIMD3<Float>(sin(angle) * radius, 0, -cos(angle) * radius)
            let box = PostboxEntity(style: .forRegion(region))
            box.root.position = spot
            box.root.orientation = simd_quatf(angle: atan2(-spot.x, -spot.z), axis: [0, 1, 0])
            let name = Locale.current.localizedString(forRegionCode: region) ?? region
            let label = ModelEntity(mesh: .generateText(name, extrusionDepth: 0.002, font: .systemFont(ofSize: 0.07, weight: .semibold), alignment: .center),
                                    materials: [UnlitMaterial(color: .white)])
            label.position = [-label.visualBounds(relativeTo: nil).extents.x / 2, box.height + 0.08, 0]
            box.root.addChild(label)
            root.addChild(box.root)
        }
    }
    #endif

    func startTracking() async {
        await head.start()
    }

    func placePalette(_ entity: Entity) {
        paletteBoard = entity
        palette.addChild(entity)
    }

    func placePostboxLabel(_ entity: Entity) {
        postbox.root.addChild(entity)
        entity.position = [0, postbox.height + 0.16, 0]
        entity.components.set(BillboardComponent())
    }

    /// Puts an empty sound / photo / note in each palette well, once the board has a size.
    private func layoutPaletteIfReady() {
        guard paletteSlots.isEmpty, let board = paletteBoard else { return }
        let size = board.visualBounds(relativeTo: palette).extents
        guard size.x > 0.05 else { return }
        for (i, kind) in ItemKind.allCases.enumerated() {
            let well = PaletteView.wellCentre(i)
            paletteSlots[kind] = [(Float(well.x / PaletteView.size.width) - 0.5) * size.x,
                                  (0.5 - Float(well.y / PaletteView.size.height)) * size.y,
                                  0.025]
            refillPalette(kind, animated: false)
        }
        let well = PaletteView.wellCentre(ItemKind.allCases.count)
        tagSlot = [(Float(well.x / PaletteView.size.width) - 0.5) * size.x,
                   (0.5 - Float(well.y / PaletteView.size.height)) * size.y,
                   0.025]
        if let pendingRecipient { setRecipient(pendingRecipient) }
    }

    /// Puts a "To" tag for the chosen contact in the palette's tag well, ready to drag onto the gift.
    func setRecipient(_ person: Person) {
        pendingRecipient = person
        guard let tagSlot else { return }
        paletteTag?.root.removeFromParent()
        let tag = GiftTagEntity(person: person, direction: .to, draggable: true)
        tag.root.position = tagSlot
        tag.root.scale = .init(repeating: 0.01)
        palette.addChild(tag.root)
        animator.pop(tag.root, to: 0.85, duration: 0.4)
        paletteTag = tag
        tagWaiting = true
    }

    private func returnTagToPalette(_ tag: GiftTagEntity) {
        guard let tagSlot else { return }
        tag.root.setParent(palette, preservingWorldTransform: true)
        let rest = Transform(scale: .init(repeating: 0.85), rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), translation: tagSlot)
        tag.root.move(to: rest, relativeTo: palette, duration: 0.35, timingFunction: .easeInOut)
    }

    private func refillPalette(_ kind: ItemKind, animated: Bool) {
        guard let slot = paletteSlots[kind] else { return }
        let e = StringItemEntity(item: .empty(kind))
        e.root.components.set(RoleComponent(role: .trayItem(kind)))
        e.root.position = slot + [0, e.hangDepth / 2 * Self.paletteScale + 0.006, 0]
        palette.addChild(e.root)
        paletteItems[kind] = e
        e.root.scale = .init(repeating: animated ? 0.01 : Self.paletteScale)
        if animated { animator.pop(e.root, to: Self.paletteScale, duration: 0.4, delay: 0.25) }
    }

    /// Sends an item that wasn't dropped on the string back into its palette well.
    private func returnToPalette(_ item: StringItemEntity) {
        let start = item.root.worldPosition
        let end = paletteSlots[item.item.kind].map { palette.convert(position: $0, to: nil) } ?? start
        SoundBank.shared.play(.pop, on: item.root, gain: -14)
        animator.run(0.4, ease: Ease.inOut) { t in
            item.root.worldPosition = simd_mix(start, end, .init(repeating: t))
            item.root.scale = .init(repeating: 1 - 0.95 * t)
        } done: { item.root.removeFromParent() }
    }

    private func updateCounts() {
        draftCount = bench.itemEntities.count
        emptyCount = bench.itemEntities.filter { !$0.item.isFilled }.count
    }

    /// While a window (an item editor, or the app panel) is open over the workshop, the workshop
    /// steps back so nothing in 3D sits in front of it. The palette is put away entirely: its
    /// SwiftUI buttons would otherwise still catch taps meant for the window, even while faded.
    func setWindowOpen(_ open: Bool) {
        // The view can report this before the RealityView has built the room; apply it after setup.
        windowOpen = open
        guard isSetUp else { return }
        for entity in [bench.root] + [outgoing?.box.root].compactMap({ $0 }) {
            animator.fade(entity, to: open ? 0.25 : 1, duration: 0.3)
            entity.setInputEnabled(!open)
        }
        if open {
            animator.fade(palette, to: 0, duration: 0.2) { [weak self] in
                // Only put it away if the window is still open when the fade finishes.
                if self?.windowOpen == true { self?.palette.isEnabled = false }
            }
        } else {
            palette.isEnabled = true
            animator.fade(palette, to: 1, duration: 0.3)
        }
    }

    /// Takes an item off the string you're making (from the viewer's "Take off" button).
    func takeOff(itemID: UUID) {
        guard let item = bench.remove(itemID: itemID, animator: animator) else { return }
        updateCounts()
        returnToPalette(item)
    }

    /// Called when the item editor window saves new content.
    func applyEdit(_ item: StringItem) {
        guard let fresh = bench.replace(item, animator: animator) else { return }
        updateCounts()
        fresh.sound()
    }

    func placeHint(_ entity: Entity) {
        hint = entity
        entity.isEnabled = false
        tableSurface.addChild(entity)
        entity.position = [0, 0.3, 0]
    }

    /// Shows a stand-in table in the simulator; on device the box lands on a real table.
    private func buildTable() {
        #if targetEnvironment(simulator)
        tableSurface.position = [0, 0.72, -0.62]
        tableSurface.isEnabled = false
        let wood = Materials.matte(Palette.wood, roughness: 0.7)
        let top = ModelEntity(mesh: .generateCylinder(height: 0.03, radius: 0.3), materials: [wood])
        top.position = [0, -0.015, 0]
        let leg = ModelEntity(mesh: .generateCylinder(height: 0.7, radius: 0.035), materials: [wood])
        leg.position = [0, -0.37, 0]
        let foot = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.2), materials: [wood])
        foot.position = [0, -0.71, 0]
        tableSurface.addChild(top)
        tableSurface.addChild(leg)
        tableSurface.addChild(foot)
        root.addChild(tableSurface)
        #else
        let anchor = AnchorEntity(.plane(.horizontal, classification: .table, minimumBounds: [0.3, 0.3]))
        anchor.addChild(tableSurface)
        root.addChild(anchor)
        Task {
            let session = SpatialTrackingSession()
            _ = await session.run(.init(tracking: [.plane]))
        }
        #endif
    }

    // MARK: Model sync

    func sync() {
        guard let model, isSetUp else { return }
        let making = model.mode == .making
        if making && !wasMaking { workshopPlaced = false }
        wasMaking = making
        workshop.isEnabled = making && workshopPlaced

        if let gift = model.pendingUnwrap, incoming == nil, headFrame() != nil {
            presentIncoming(gift)
        }

        let wanted = Set(model.hung.map(\.id))
        for hung in model.hung where hungEntities[hung.id] == nil {
            let entity = HangingStringEntity(id: hung.id, items: hung.string.items, revealed: true)
            entity.root.position = hung.position
            entity.root.orientation = simd_quatf(angle: hung.yaw, axis: [0, 1, 0])
            root.addChild(entity.root)
            hungEntities[hung.id] = entity
        }
        for (id, entity) in hungEntities where !wanted.contains(id) {
            // Retired to the shelf: drift up and fade away.
            hungEntities[id] = nil
            animator.fade(entity.root, to: 0, duration: 0.8) { entity.root.removeFromParent() }
        }
    }

    // MARK: Frame update

    func tick(_ dt: Float) {
        animator.tick(dt)
        layoutPaletteIfReady()
        if wasMaking && !workshopPlaced, let (eye, yaw) = headFrame() {
            workshop.position = eye
            workshop.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            workshopPlaced = true
            workshop.isEnabled = true
        }
        if incoming == nil, let gift = model?.pendingUnwrap, headFrame() != nil {
            presentIncoming(gift)
        }
        updateGaze(dt)
    }

    // MARK: Making

    func wrap() {
        guard outgoing == nil, !bench.itemEntities.isEmpty, emptyCount == 0 else { return }
        let string = LoveString(senderName: "Me", recipientName: "You", items: bench.items)
        let box = GiftBoxEntity(stage: .open)
        box.root.position = Self.outgoingRest
        workshop.addChild(box.root)
        outgoing = (box, string)
        hasOutgoingBox = true
        giftAddressed = false

        let target = box.root.worldPosition + [0, 0.04, 0]
        let entities = bench.itemEntities
        for (i, e) in entities.enumerated() {
            let start = e.root.worldPosition
            animator.run(0.55, delay: Float(i) * 0.06) { t in
                e.root.worldPosition = simd_mix(start, target, .init(repeating: t)) + [0, 0.1 * sin(.pi * t), 0]
                e.root.scale = .init(repeating: 1 - 0.85 * t)
            }
        }
        let flightEnd = Float(entities.count) * 0.06 + 0.55
        animator.run(flightEnd, step: { _ in }) { [weak self] in
            guard let self else { return }
            bench.removeAll()
            updateCounts()
            box.wrapUp(animator: animator) {
                box.root.components.set(RoleComponent(role: .outgoingBox))
            }
        }
    }

    func clearDraft() {
        for e in bench.itemEntities {
            animator.pop(e.root, to: 0.01, duration: 0.25)
        }
        animator.run(0.3, step: { _ in }) { [weak self] in
            self?.bench.removeAll()
            self?.updateCounts()
        }
    }

    // MARK: Gestures

    private struct DragState {
        enum Kind { case item(StringItemEntity), outgoingBox, postbox, hungString(HangingStringEntity), tag(GiftTagEntity) }
        let kind: Kind
        let entity: Entity
        var offset: SIMD3<Float>
        var samples: [(position: SIMD3<Float>, time: TimeInterval)] = []
    }

    func dragChanged(_ hit: Entity, at location: SIMD3<Float>, time: TimeInterval) {
        if drag == nil {
            guard let started = beginDrag(hit, at: location) else { return }
            drag = started
        }
        guard var d = drag else { return }
        var target = location + d.offset
        if case .postbox = d.kind { target.y = 0 }
        d.entity.worldPosition = target
        d.samples.append((target, time))
        d.samples.removeAll { time - $0.time > 0.15 }
        drag = d
        switch d.kind {
        case .postbox: facePostboxTowardsUser()
        case .item:
            let over = bench.accepts(worldPoint: target, eye: head.position)
            bench.setHighlighted(over)
            bench.setGap(over ? bench.insertionIndex(forWorld: target, eye: head.position) : nil, animator: animator)
        case .outgoingBox: setOverPostbox(looksOver(postbox.worldBounds, target))
        case .tag:
            let over = outgoing.map { looksOver($0.box.root.visualBounds(relativeTo: nil), target) } ?? false
            if let box = outgoing?.box.root { animator.pop(box, to: over ? 1.08 : 1, duration: 0.2) }
        default: break
        }
    }

    private func beginDrag(_ hit: Entity, at location: SIMD3<Float>) -> DragState? {
        guard let (carrier, role) = hit.roleCarrier() else { return nil }
        switch role {
        case .trayItem(let kind):
            guard let taken = paletteItems.removeValue(forKey: kind) else { return nil }
            refillPalette(kind, animated: true)
            return carry(taken, at: location)

        case .stringItem(let stringID, let itemID) where stringID == bench.id:
            guard let taken = bench.remove(itemID: itemID, animator: animator) else { return nil }
            updateCounts()
            return carry(taken, at: location)

        case .stringItem(let stringID, _), .twine(let stringID):
            guard let hung = hungEntities[stringID] else { return nil }
            return DragState(kind: .hungString(hung), entity: hung.root, offset: hung.root.worldPosition - location)

        case .outgoingBox:
            SoundBank.shared.play(.rustle, on: carrier, gain: -14)
            return DragState(kind: .outgoingBox, entity: carrier, offset: carrier.worldPosition - location)

        case .postbox:
            return DragState(kind: .postbox, entity: carrier, offset: carrier.worldPosition - location)

        case .giftTag:
            guard let tag = paletteTag, tag.root === carrier else { return nil }
            tag.root.setParent(workshop, preservingWorldTransform: true)
            tag.root.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            animator.pop(tag.root, to: 1, duration: 0.2)
            return DragState(kind: .tag(tag), entity: tag.root, offset: tag.root.worldPosition - location)

        default:
            return nil
        }
    }

    private func carry(_ item: StringItemEntity, at location: SIMD3<Float>) -> DragState {
        item.root.setParent(workshop, preservingWorldTransform: true)
        item.root.orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        animator.pop(item.root, to: 1.15, duration: 0.2)
        return DragState(kind: .item(item), entity: item.root, offset: item.root.worldPosition - location)
    }

    func dragEnded() {
        guard let d = drag else { return }
        drag = nil
        switch d.kind {
        case .item(let item):
            bench.setHighlighted(false)
            if bench.accepts(worldPoint: item.root.worldPosition, eye: head.position) {
                bench.insert(item, atWorld: item.root.worldPosition, eye: head.position, animator: animator)
                updateCounts()
                SoundBank.shared.play(.pop, on: item.root, gain: -10)
            } else {
                bench.setGap(nil, animator: animator)
                returnToPalette(item)
            }

        case .outgoingBox:
            let dropped = isOverPostbox
            setOverPostbox(false)
            throwBox(velocity: velocity(of: d.samples), droppedOnPostbox: dropped)

        case .postbox:
            model?.postboxPosition = postbox.root.worldPosition

        case .hungString(let hung):
            model?.move(hungID: hung.id, to: hung.root.worldPosition)

        case .tag(let tag):
            // Tags only tie onto a wrapped gift; anywhere else they go back to the palette.
            if let (box, string) = outgoing, looksOver(box.root.visualBounds(relativeTo: nil), tag.root.worldPosition) {
                animator.pop(box.root, to: 1, duration: 0.2)
                box.attachTag(GiftTagEntity(person: tag.person, direction: .to, draggable: false), animator: nil)
                tag.root.removeFromParent()
                paletteTag = nil
                pendingRecipient = nil
                tagWaiting = false
                var addressed = string
                addressed.recipient = tag.person
                addressed.recipientName = tag.person.name
                outgoing = (box, addressed)
                giftAddressed = true
                needsTagNudge = false
                SoundBank.shared.play(.pop, on: box.root, gain: -8)
            } else {
                if let box = outgoing?.box.root { animator.pop(box, to: 1, duration: 0.2) }
                returnTagToPalette(tag)
            }
        }
    }

    func tap(_ hit: Entity) {
        guard let (_, role) = hit.roleCarrier() else { return }
        switch role {
        case .incomingBox:
            advanceUnwrap()
        case .giftTag:
            model?.contactPickerRequested = true
        case .stringItem(let stringID, let itemID):
            if let hung = hungEntities[stringID], let index = hung.itemEntities.firstIndex(where: { $0.item.id == itemID }) {
                focus(hung, index: index)
                model?.viewingItem = ItemViewRequest(item: hung.itemEntities[index].item, editable: false)
                let item = hung.itemEntities[index]
                animator.run(0.01, delay: 1.5, step: { _ in }) { [weak self] in
                    guard let self, gaze.active?.string != stringID || gaze.active?.index != index else { return }
                    item.setActive(false, animator: animator)
                }
            } else if let item = bench.entity(for: itemID)?.item {
                // Tap an item on the string you're making: fill it if empty, otherwise look at it.
                if item.isFilled {
                    model?.viewingItem = ItemViewRequest(item: item, editable: true)
                } else {
                    model?.editingItem = item
                }
            }
        default:
            break
        }
    }

    // MARK: Throwing

    private func velocity(of samples: [(position: SIMD3<Float>, time: TimeInterval)]) -> SIMD3<Float> {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.01 else { return .zero }
        return (last.position - first.position) / Float(last.time - first.time)
    }

    /// True when, from where you're standing, the held box is over the postbox.
    /// Depth is ignored: it's hard to judge, and in the simulator drags can't change it at all.
    private func looksOver(_ bounds: BoundingBox, _ p: SIMD3<Float>) -> Bool {
        guard let eye = head.position else { return bounds.contains(p) }
        let lo = bounds.min - 0.12, hi = bounds.max + 0.12
        let dir = simd_normalize(p - eye)
        // March along the line of sight and see whether it passes through the postbox.
        var d: Float = 0.2
        while d < 8 {
            let q = eye + dir * d
            if all(q .>= lo) && all(q .<= hi) { return true }
            d += 0.04
        }
        return false
    }

    private func setOverPostbox(_ over: Bool) {
        guard over != isOverPostbox else { return }
        isOverPostbox = over
        animator.pop(postbox.root, to: over ? 1.06 : 1, duration: 0.25)
    }

    private func throwBox(velocity v: SIMD3<Float>, droppedOnPostbox: Bool) {
        guard let (box, string) = outgoing else { return }
        let start = box.root.worldPosition
        let slot = postbox.slotWorld
        let toSlot = slot - start
        let distance = simd_length(toSlot)
        let speed = simd_length(v)
        let aimed = speed > 0.5 && simd_dot(simd_normalize(v), simd_normalize(toSlot)) > cos(Float.pi * 0.3)

        // No tag, no posting: it wouldn't know where to go.
        if giftAddressed == false && (droppedOnPostbox || distance < 0.35 || aimed) {
            needsTagNudge = true
            var rest = box.root.transform
            rest.translation = Self.outgoingRest
            box.root.move(to: rest, relativeTo: workshop, duration: 0.6, timingFunction: .easeInOut)
            return
        }
        guard droppedOnPostbox || distance < 0.35 || aimed else {
            // Missed (or just let go): drift gently back to the bench.
            var rest = box.root.transform
            rest.translation = Self.outgoingRest
            box.root.move(to: rest, relativeTo: workshop, duration: 0.6, timingFunction: .easeInOut)
            return
        }

        outgoing = nil
        hasOutgoingBox = false
        giftAddressed = false
        box.root.components.remove(RoleComponent.self)
        SoundBank.shared.play(.whoosh, on: box.root)
        let height = 0.2 + distance * 0.15
        let duration = min(max(distance / max(speed, 1.4), 0.5), 1.1)
        let spin = simd_quatf(angle: Float.random(in: -1...1), axis: [0, 1, 0])
        animator.run(duration, ease: Ease.linear) { t in
            let p = simd_mix(start, slot, .init(repeating: t)) + [0, height * 4 * t * (1 - t), 0]
            box.root.worldPosition = p
            box.root.orientation = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), spin, t)
            box.root.scale = .init(repeating: t < 0.7 ? 1 : 1 - (t - 0.7) / 0.3 * 0.8)
        } done: { [weak self] in
            guard let self else { return }
            box.root.removeFromParent()
            postbox.gulp(animator: animator)
            model?.post(string)
        }
    }

    private func placePostbox(at p: SIMD3<Float>) {
        postbox.root.position = p
        facePostboxTowardsUser()
    }

    private func facePostboxTowardsUser() {
        let p = postbox.root.position
        postbox.root.orientation = simd_quatf(angle: atan2(-p.x, -p.z), axis: [0, 1, 0])
    }

    // MARK: Unwrapping

    private func presentIncoming(_ gift: LoveString) {
        #if targetEnvironment(simulator)
        // Pull the stand-in table up in front of wherever you are.
        if let (eye, yaw) = headFrame() {
            let rotation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            tableSurface.position = SIMD3(eye.x, eye.y - 0.38, eye.z) + rotation.act([0, 0, -0.85])
            tableSurface.orientation = rotation
        }
        #endif
        let box = GiftBoxEntity(stage: .wrapped)
        box.root.components.set(RoleComponent(role: .incomingBox))
        box.attachTag(GiftTagEntity(person: gift.sender ?? Person(name: gift.senderName), direction: .from, draggable: false),
                      animator: nil)
        box.root.position = [0, 0.4, 0]
        box.root.scale = .init(repeating: 0.01)
        tableSurface.addChild(box.root)
        incoming = (box, gift)
        isUnwrapping = true
        tableSurface.isEnabled = true
        hint?.isEnabled = true

        #if DEBUG
        // `-demo reveal`: tap through the unwrap automatically, for simulator checks.
        if ["reveal", "welcome"].contains(UserDefaults.standard.string(forKey: "demo")) {
            for step in 1...3 {
                animator.run(0.01, delay: 1.5 * Float(step), step: { _ in }) { [weak self] in self?.advanceUnwrap() }
            }
        }
        #endif

        // Float down onto the table.
        animator.pop(box.root, to: 1, duration: 0.5)
        animator.run(0.9, ease: Ease.out) { t in
            box.root.position = [0, 0.4 * (1 - t), 0]
        } done: {
            SoundBank.shared.play(.clunk, on: box.root, gain: -16)
        }
    }

    private func advanceUnwrap() {
        guard let (box, _) = incoming else { return }
        hint?.isEnabled = false
        box.advanceUnwrap(animator: animator) { [weak self] stage in
            if stage == .unwrapped { self?.releaseString() }
        }
    }

    /// The string floats up out of the open box and hangs itself in front of you, still dark.
    private func releaseString() {
        guard let (box, gift) = incoming, let model else { return }
        let string = HangingStringEntity(id: gift.id, items: gift.items, revealed: false)
        let start = box.root.worldPosition + [0, 0.08, 0]
        string.root.worldPosition = start
        string.root.scale = .init(repeating: 0.05)
        root.addChild(string.root)
        hungEntities[gift.id] = string

        let (end, yaw) = hangSpot()
        string.root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        SoundBank.shared.play(.chime(0), on: string.root)
        animator.run(1.4) { t in
            string.root.worldPosition = simd_mix(start, end, .init(repeating: t)) + [0, 0.15 * sin(.pi * t), 0]
            string.root.scale = .init(repeating: 0.05 + 0.95 * t)
        } done: { [weak self] in
            guard let self else { return }
            model.hang(gift, at: end, yaw: yaw)
            model.pendingUnwrap = nil
            incoming = nil
            isUnwrapping = false
            animator.pop(box.root, to: 0.01, duration: 0.4, delay: 0.3) { [weak self] in
                box.root.removeFromParent()
                #if targetEnvironment(simulator)
                if self?.incoming == nil { self?.tableSurface.isEnabled = false }
                #endif
            }
        }
    }

    /// Eye position and the yaw that turns an entity's -Z towards where the wearer faces.
    private func headFrame() -> (SIMD3<Float>, Float)? {
        // The first poses after tracking starts can be an identity transform at the floor; wait for a real head.
        guard let eye = head.position, eye.y > 0.4, var forward = head.forward else { return nil }
        forward.y = 0
        guard simd_length(forward) > 0.01 else { return nil }
        forward = simd_normalize(forward)
        return (eye, atan2(-forward.x, -forward.z))
    }

    /// Behind and just above where the workshop string goes, at eye height, facing the wearer.
    private func hangSpot() -> (SIMD3<Float>, Float) {
        let origin = head.position ?? [0, 1.5, 0]
        var forward = head.forward ?? [0, 0, -1]
        forward.y = 0
        forward = simd_length(forward) > 0.01 ? simd_normalize(forward) : [0, 0, -1]
        let offset = Float(hungEntities.count - 1) * 0.08
        let spot = SIMD3<Float>(origin.x, origin.y + 0.06 + offset, origin.z) + forward * 1.5
        let toUser = origin - spot
        return (spot, atan2(toUser.x, toUser.z))
    }

    // MARK: Head-driven playback

    private struct GazeState {
        var candidate: (string: UUID, index: Int)?
        var dwell: Float = 0
        var active: (string: UUID, index: Int)?
    }

    private func updateGaze(_ dt: Float) {
        guard let eye = head.position, let forward = head.forward else { return }
        var best: (UUID, Int, Float)?
        for (id, string) in hungEntities {
            for (i, item) in string.itemEntities.enumerated() {
                let to = item.root.worldPosition + [0, -item.hangDepth / 2, 0] - eye
                let distance = simd_length(to)
                guard distance < 3.5 else { continue }
                let angle = acos(min(max(simd_dot(to / distance, forward), -1), 1))
                if angle < 0.12, angle < (best?.2 ?? .infinity) { best = (id, i, angle) }
            }
        }

        let hit = best.map { (string: $0.0, index: $0.1) }
        if hit?.string == gaze.candidate?.string, hit?.index == gaze.candidate?.index {
            gaze.dwell += dt
        } else {
            gaze.candidate = hit
            gaze.dwell = 0
        }
        guard gaze.dwell > 0.2 else { return }
        if gaze.active?.string != hit?.string || gaze.active?.index != hit?.index {
            if let old = gaze.active, let string = hungEntities[old.string], old.index < string.itemEntities.count {
                string.itemEntities[old.index].setActive(false, animator: animator)
            }
            gaze.active = hit
            if let hit, let string = hungEntities[hit.string] { focus(string, index: hit.index) }
        }
    }

    /// Brings one item to life. Anything to its left that hasn't been seen yet lights up first,
    /// in a quick left-to-right cascade, so the string always unfolds in order.
    private func focus(_ string: HangingStringEntity, index: Int) {
        let items = string.itemEntities
        guard index < items.count else { return }
        var delay: Float = 0
        for i in 0...index where !items[i].isRevealed {
            let item = items[i]
            animator.run(0.01, delay: delay, step: { _ in }) { [animator] in
                item.setRevealed(true, animator: animator)
                item.sound()
            }
            delay += 0.18
        }
        let target = items[index]
        if delay == 0 { target.sound() }
        target.setActive(true, animator: animator)
    }
}
