//
//  RoomDetailViewController.swift
//  Flat
//
//  Created by xuyunshi on 2021/11/1.
//  Copyright © 2021 agora.io. All rights reserved.
//


import UIKit
import RxSwift

class RoomDetailViewController: UIViewController {
    enum RoomOperation {
        case modify
        case remove
        case cancel
        
        var isDestructive: Bool {
            if self == .cancel || self == .remove { return true }
            return false
        }
        
        var title: String {
            switch self {
            case .cancel:
                return NSLocalizedString("Cancel Room", comment: "")
            case .remove:
                return NSLocalizedString("Remove From List", comment: "")
            case .modify:
                return NSLocalizedString("Modify Room", comment: "")
            }
        }
        
        var alertVerbose: String {
            switch self {
            case .modify:
                return ""
            case .remove:
                return NSLocalizedString("Remove Room Verbose", comment: "")
            case .cancel:
                return NSLocalizedString("Cancel Room Verbose", comment: "")
            }
        }
        
        var image: UIImage? {
            switch self {
            case .modify:
                return nil
            case .remove:
                return UIImage(named: "delete_room")
            case .cancel:
                return nil
            }
        }
        
        func actionFor(viewController: RoomDetailViewController) {
            switch self {
            case .modify:
                // TODO: Modify Room 
                return
            case .remove, .cancel:
                let hud = viewController.showActivityIndicator()
                let api = RoomCancelRequest(roomUUID: viewController.info.roomUUID)
                ApiProvider.shared.request(fromApi: api) { result in
                    switch result {
                    case .success:
                        NotificationCenter.default.post(name: .init(rawValue: homeShouldUpdateListNotification), object: nil)
                        hud.stopAnimating()
                        
                        viewController.navigationController?.popViewController(animated: true)
                        viewController.mainContainer?.removeTop()
                    case .failure(let error):
                        hud.stopAnimating()
                        viewController.toast(error.localizedDescription)
                    }
                }
            }
        }
        
        static func actionsWith(isTeacher: Bool, roomStatus: RoomStartStatus) -> [RoomOperation] {
            switch roomStatus {
            case .Idle:
                if isTeacher {
                    return [.modify, .cancel]
                } else {
                    return [.remove]
                }
            case .Started, .Paused:
                if isTeacher {
                    return []
                } else {
                    return [.remove]
                }
            default:
                return []
            }
        }
    }
    
    var info: RoomBasicInfo
    var availableOperations: [RoomOperation] = []
    
    let deviceStatusStore: UserDevicePreferredStatusStore
    
    var cameraOn: Bool
    
    var micOn: Bool
    
    func updateStatus(_ status: RoomStartStatus) {
        info.roomStatus = status
        if isViewLoaded {
            updateEnterRoomButtonTitle()
        }
    }
    
    init(info: RoomBasicInfo) {
        self.info = info
        deviceStatusStore = UserDevicePreferredStatusStore(userUUID: AuthStore.shared.user?.userUUID ?? "")
        self.cameraOn = deviceStatusStore.getDevicePreferredStatus(.camera)
        self.micOn = deviceStatusStore.getDevicePreferredStatus(.mic)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    // MARK: - LifeCycle
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData { _ in
            self.updateViewWithCurrentStatus()
            self.updateAvailableActions()
            self.updateEnterRoomButtonTitle()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        mainStackView.axis = view.bounds.width <= 428 ? .vertical : .horizontal
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        inviteButton.layer.borderColor = UIColor.borderColor.cgColor
        replayButton.layer.borderColor = UIColor.borderColor.cgColor
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        updateViewWithCurrentStatus()
        updateAvailableActions()
        updateEnterRoomButtonTitle()
    }
    
    // MARK: - Private
    func loadData(completion: @escaping ((Result<RoomBasicInfo, ApiError>)->Void)) {
        RoomBasicInfo.fetchInfoBy(uuid: info.roomUUID, periodicUUID: info.periodicUUID) { result in
            switch result {
            case .success(let detail):
                self.info = detail
                completion(.success(detail))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func updateAvailableActions() {
        let isTeacher = info.isOwner
        availableOperations = RoomOperation.actionsWith(isTeacher: isTeacher, roomStatus: info.roomStatus)
        if availableOperations.isEmpty {
            navigationItem.rightBarButtonItem = nil
        } else {
            let item = UIBarButtonItem(image: UIImage(named: "more"),
                                       style: .plain,
                                       target: nil,
                                       action: nil)
            var actions = availableOperations.map { operation -> Action in
                Action(title: operation.title,
                       image: operation.image,
                       style: operation.isDestructive ? .destructive : .default,
                       handler: { _ in
                    if !operation.alertVerbose.isEmpty {
                        self.showCheckAlert(title: operation.title, message: operation.alertVerbose) {
                            operation.actionFor(viewController: self)
                        }
                    } else {
                        operation.actionFor(viewController: self)
                    }
                })
            }
            actions.append(.cancel)
            item.setupCommonCustomAlert(actions)
            item.viewContainingControllerProvider = { [weak self]  in
                return self
            }
            navigationItem.rightBarButtonItem = item
        }
    }
    
    @IBAction func onClickCopy(_ sender: Any) {
        UIPasteboard.general.string = info.formatterInviteCode
        toast(localizeStrings("Copy Success"))
    }
    
    func setupViews() {
        title = info.title
        
        view.backgroundColor = .color(type: .background, .weak)
        func loopTextColor(view: UIView) {
            if let stack = view as? UIStackView {
                stack.backgroundColor = self.view.backgroundColor
                stack.arrangedSubviews.forEach { loopTextColor(view: $0) }
            } else if let label = view as? UILabel {
                if label.font.pointSize >= 16 {
                    label.textColor = .color(type: .text, .strong)
                } else {
                    label.textColor = .color(type: .text)
                }
            } else if let imageView = view as? UIImageView {
                imageView.tintColor = .color(type: .text)
            } else if let button = view as? UIButton {
                button.tintColor = .color(type: .text)
            } else {
                view.subviews.forEach { loopTextColor(view: $0) }
            }
        }
        
        loopTextColor(view: mainStackView)
        
        let line = UIView()
        line.backgroundColor = .borderColor
        view.addSubview(line)
        line.snp.makeConstraints { make in
            make.left.right.equalTo(mainStackView)
            make.top.equalTo(mainStackView.snp.bottom).offset(16)
            make.height.equalTo(1)
        }
    }
    
    func updateEnterRoomButtonTitle() {
        if self.info.isOwner, info.roomStatus == .Idle {
            self.enterRoomButton.setTitle(NSLocalizedString("Start Class", comment: ""), for: .normal)
        } else {
            self.enterRoomButton.setTitle(NSLocalizedString("Enter Room", comment: ""), for: .normal)
        }
    }
    
    func updateViewWithCurrentStatus() {
        let beginTime: Date
        let endTime: Date
        let status: RoomStartStatus
        let roomType: ClassRoomType
        beginTime = info.beginTime
        endTime = info.endTime
        status = info.roomStatus
        roomType = info.roomType
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: beginTime) + "~" + formatter.string(from: endTime)
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        let dateStr = formatter.string(from: beginTime)
        timeLabel.text = dateStr + " " + timeStr
        statusLabel.text = NSLocalizedString(status.rawValue, comment: "")
        
        roomNumberLabel.text = info.formatterInviteCode
        roomTypeLabel.text = NSLocalizedString(roomType.rawValue, comment: "")
        
        if status == .Stopped {
            replayButton.isHidden = info.hasRecord
            roomOperationStackView.arrangedSubviews.forEach {
                $0.isHidden = $0 === replayButton ? false : true
            }
        } else {
            replayButton.isHidden = true
        }
    }
    
    // MARK: - Action
    @IBAction func onClickReplay() {
        showActivityIndicator()
        ApiProvider.shared.request(fromApi: RecordDetailRequest(uuid: info.roomUUID)) { [weak self] result in
            guard let self = self else { return }
            self.stopActivityIndicator()
            switch result {
            case .success(let recordInfo):
                let vc = ReplayViewController(info: recordInfo)
                self.mainContainer?.concreteViewController.present(vc, animated: true, completion: nil)
            case .failure(let error):
                self.toast(error.localizedDescription)
            }
        }
    }
    
    @IBAction func onClickInvite(_ sender: UIButton) {
        let vc = ShareManager.createShareActivityViewController(roomUUID: info.roomUUID,
                                                                beginTime: info.beginTime,
                                                                title: info.title,
                                                                roomNumber: info.inviteCode)
        popoverViewController(viewController: vc, fromSource: sender)
    }
    
    @IBAction func onClickEnterRoom(_ sender: Any) {
        enterRoomButton.isEnabled = false
        
        // Join room
        RoomPlayInfo.fetchByJoinWith(uuid: info.roomUUID, periodicUUID: info.periodicUUID) { [weak self] result in
            guard let self = self else { return }
            self.enterRoomButton.isEnabled = true
            switch result {
            case .success(let playInfo):
                let vc = ClassroomFactory.getClassRoomViewController(withPlayInfo: playInfo,
                                                                     detailInfo: self.info,
                                                                     deviceStatus: .init(mic: self.micOn, camera: self.cameraOn))
                self.mainContainer?.concreteViewController.present(vc, animated: true, completion: nil)
            case .failure(let error):
                self.showAlertWith(message: error.localizedDescription)
            }
        }
    }
    
    @IBOutlet weak var inviteButton: UIButton!
    @IBOutlet weak var roomNumberTitleLabel: UILabel!
    @IBOutlet weak var enterRoomButton: UIButton!
    @IBOutlet weak var mainStackView: UIStackView!
    @IBOutlet weak var roomTypeLabel: UILabel!
    @IBOutlet weak var roomNumberLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var roomOperationStackView: UIStackView!
    @IBOutlet weak var replayButton: UIButton!
}
