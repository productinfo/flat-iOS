//
//  FastboardViewController.swift
//  Flat
//
//  Created by xuyunshi on 2022/1/12.
//  Copyright © 2022 agora.io. All rights reserved.
//

import Fastboard
import RxRelay
import RxSwift
import UIKit
import Whiteboard
import SnapKit

func tryPreloadWhiteboard() {
    DispatchQueue.main.async {
        // Load once to reduce first time join room
        _ = WhiteBoardView(frame: .zero)
    }
}

struct WhiteboardPermission: Equatable {
    let writable: Bool
    let inputEnable: Bool
}

class FastboardViewController: UIViewController {
    let fastRoom: FastRoom
    let isRoomJoined: BehaviorRelay<Bool> = .init(value: false)
    let isRoomBanned: BehaviorRelay<Bool> = .init(value: false)
    let roomPermission: BehaviorRelay<WhiteboardPermission>
    let roomError: PublishRelay<FastRoomError> = .init()

    /// Setup this store after whiteboard joined
    weak var bindStore: ClassRoomSyncedStore?
    var appsClickHandler: ((WhiteRoom, UIButton) -> Void)?

    // MARK: Public

    func leave() {
        fastRoom.disconnectRoom()
    }
    
    func updateRoomPermission(_ permission: WhiteboardPermission) -> Single<(WhiteboardPermission)> {
        guard let w = fastRoom.room?.isWritable else { return .just(permission) }
        logger.info("update whiteboard permission \(permission)")
        fastRoom.room?.disableDeviceInputs(!permission.inputEnable)
        if w != permission.writable {
            return .create { [weak self] ob in
                guard let self else {
                    ob(.failure("self not exist"))
                    return Disposables.create()
                }
                logger.info("update writable success \(permission.writable)")
                self.fastRoom.updateWritable(permission.writable) { [weak self] error in
                    if let error {
                        ob(.failure(error))
                    } else {
                        ob(.success(permission))
                        self?.roomPermission.accept(permission)
                    }
                }
                return Disposables.create()
            }
        } else {
            return .just(permission)
        }
    }

    func bind(observablePermission: Observable<WhiteboardPermission>) -> Observable<WhiteboardPermission> {
        Observable.combineLatest(observablePermission, isRoomJoined)
            .filter(\.1)
            .map(\.0)
            .distinctUntilChanged()
            .concatMap { [weak self] permission -> Observable<WhiteboardPermission> in
                guard let self else { return .error("self not exist") }
                return self.updateRoomPermission(permission).asObservable()
            }.do(onNext: { [weak self] permission in
                self?.fastRoom.setAllPanel(hide: !permission.inputEnable)
                self?.fastRoom.room?.disableCameraTransform(!permission.inputEnable)
            })
    }

    init(fastRoomConfiguration: FastRoomConfiguration) {
        fastRoom = Fastboard.createFastRoom(withFastRoomConfig: fastRoomConfiguration)
        roomPermission = .init(value: .init(writable: fastRoomConfiguration.whiteRoomConfig.isWritable,
                                            inputEnable: fastRoomConfiguration.whiteRoomConfig.isWritable))
        super.init(nibName: nil, bundle: nil)
        fastRoom.delegate = self
        logger.trace("\(self)")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        logger.trace("\(self), deinit")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        joinRoom()
        bindConnecting()
        setupGestures()
    }

    var regularUndoLeftMargin: Constraint?
    var regularRightSceneMargin: Constraint?
    let boardMargin: CGFloat = 8
    func updateUndoAndSceneConstraints() {
        if #available(iOS 14.0, *) {
            if ProcessInfo().isiOSAppOnMac { return }
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            if isOnPadSplitScreen {
                regularUndoLeftMargin?.update(inset: 88)
                regularRightSceneMargin?.update(inset: 88)
            } else {
                regularUndoLeftMargin?.update(inset: boardMargin)
                regularRightSceneMargin?.update(inset: boardMargin)
            }
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateUndoAndSceneConstraints()
    }
    
    // MARK: - Private
    func joinRoom() {
        fastRoom.joinRoom { [weak self] result in
            switch result {
            case let .success(room):
                self?.isRoomJoined.accept(true)
                if let relatedStore = self?.bindStore {
                    relatedStore.setup(with: room)
                }
            case .failure:
                return
            }
        }
    }

    @objc
    fileprivate func onUndoRedoGesture(_ g: UITapGestureRecognizer) {
        if g === undoGesture {
            fastRoom.room?.undo()
        }
        if g === redoGesture {
            fastRoom.room?.redo()
        }
    }

    @objc
    fileprivate func onUndoRedoShortcutsUpdate(notification: Notification) {
        guard let disable = notification.userInfo?["disable"] as? Bool else { return }
        updateUndoRedoGestureDisable(disable)
    }

    fileprivate func updateUndoRedoGestureDisable(_ disabled: Bool) {
        [undoGesture, redoGesture].forEach { $0.isEnabled = !disabled }
    }

    fileprivate func setupGestures() {
        view.addGestureRecognizer(undoGesture)
        view.addGestureRecognizer(redoGesture)
        updateUndoRedoGestureDisable(ShortcutsManager.shared.shortcuts[.disableDefaultUndoRedo] ?? false)
        NotificationCenter.default.addObserver(self, selector: #selector(onUndoRedoShortcutsUpdate(notification:)), name: undoRedoShortcutsUpdateNotificaton, object: nil)
    }

    func bindConnecting() {
        isRoomJoined
            .asDriver()
            .distinctUntilChanged()
            .drive(with: self, onNext: { weakSelf, isJoin in
                if isJoin {
                    weakSelf.stopActivityIndicator()
                } else {
                    weakSelf.showActivityIndicator()
                }
            })
            .disposed(by: rx.disposeBag)
    }
    
    func setupViews() {
        view.addSubview(fastRoom.view)
        fastRoom.view.snp.makeConstraints { $0.edges.equalToSuperview() }

        let appsItem = JustExecutionItem(image: UIImage(named: "whiteboard_apps")!, action: { [weak self] room, value in
            self?.fastRoom.view.overlay?.dismissAllSubPanels()
            if let button = value as? UIButton {
                self?.appsClickHandler?(room, button)
            }
        }, identifier: "whiteboard_apps")

        RegularFastRoomOverlay.customOperationPanel = {
            var items = RegularFastRoomOverlay.defaultOperationPanelItems
            items.append(appsItem)
            return FastRoomPanel(items: items)
        }
    }

    // MARK: - Lazy

    lazy var undoGesture: UITapGestureRecognizer = {
        let double = UITapGestureRecognizer(target: self, action: #selector(onUndoRedoGesture))
        double.numberOfTouchesRequired = 2
        double.delegate = self
        return double
    }()

    lazy var redoGesture: UITapGestureRecognizer = {
        let triple = UITapGestureRecognizer(target: self, action: #selector(onUndoRedoGesture))
        triple.numberOfTouchesRequired = 3
        triple.delegate = self
        return triple
    }()
}

extension FastboardViewController: FastRoomDelegate {
    func fastboardDidJoinRoomSuccess(_: FastRoom, room _: WhiteRoom) {}

    func fastboardUserKickedOut(_: FastRoom, reason _: String) {
        // For this error is caused by server closing, it should be noticed by teacher.
        isRoomBanned.accept(true)
    }

    func fastboardPhaseDidUpdate(_: FastRoom, phase: FastRoomPhase) {
        logger.info("phase update \(phase)")
        switch phase {
        case .connecting, .reconnecting, .disconnecting, .disconnected:
            isRoomJoined.accept(false)
        case .connected:
            isRoomJoined.accept(true)
        case .unknown:
            return
        }
    }

    func fastboardDidOccurError(_: FastRoom, error: FastRoomError) {
        roomError.accept(error)
    }

    func fastboardDidSetupOverlay(_ fastboard: FastRoom, overlay: FastRoomOverlay?) {
        if let overlay = overlay as? RegularFastRoomOverlay {
            overlay.invalidAllLayout()
            overlay.operationPanel.view?.snp.makeConstraints { make in
                make.centerY.equalTo(fastboard.view.whiteboardView)
                make.left.equalTo(fastboard.view.whiteboardView).inset(boardMargin)
            }

            overlay.deleteSelectionPanel.view?.snp.makeConstraints { make in
                make.left.equalTo(overlay.operationPanel.view!)
                make.bottom.equalTo(overlay.operationPanel.view!.snp.top).offset(-boardMargin)
            }

            overlay.undoRedoPanel.view?.snp.makeConstraints { make in
                make.bottom.equalTo(fastboard.view.whiteboardView).inset(boardMargin)
                self.regularUndoLeftMargin = make.left.equalToSuperview().inset(boardMargin).constraint
            }

            overlay.scenePanel.view?.snp.makeConstraints { make in
                make.bottom.equalTo(fastboard.view.whiteboardView).inset(boardMargin)
                self.regularRightSceneMargin = make.right.equalToSuperview().inset(boardMargin).constraint
            }
            updateUndoAndSceneConstraints()
        }

        if let overlay = overlay as? CompactFastRoomOverlay {
            overlay.undoRedoPanel.view?.direction = .vertical

            overlay.setPanelItemHide(item: .operationType(.previousPage)!, hide: true)
            overlay.setPanelItemHide(item: .operationType(.pageIndicator)!, hide: true)
            overlay.setPanelItemHide(item: .operationType(.nextPage)!, hide: true)
            overlay.setPanelItemHide(item: .operationType(.newPage)!, hide: true)

            overlay.invalidAllLayout()

            overlay.operationPanel.view?.snp.makeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalToSuperview().inset(8)
            }

            overlay.colorAndStrokePanel.view?.snp.makeConstraints { make in
                make.bottom.equalTo(overlay.operationPanel.view!.snp.top).offset(-8)
                make.left.equalToSuperview().inset(8)
            }

            overlay.deleteSelectionPanel.view?.snp.makeConstraints { make in
                make.bottom.equalTo(overlay.operationPanel.view!.snp.top).offset(-8)
                make.left.equalToSuperview().inset(8)
            }

            overlay.undoRedoPanel.view?.snp.makeConstraints { make in
                make.left.equalToSuperview().inset(8)
                make.top.equalTo(overlay.operationPanel.view!.snp.bottom).offset(8)
            }
        }
    }
}

extension FastRoomPhase: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting:
            return "reconnecting"
        case .disconnecting:
            return "disconnecting"
        case .disconnected:
            return "disconnected"
        case .unknown:
            return "unknown \(rawValue)"
        }
    }
}

extension FastboardViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }
}
