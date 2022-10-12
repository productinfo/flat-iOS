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
    var info: RoomBasicInfo?
    var hideAllActions = false
    
    func updateStatus(_ status: RoomStartStatus) {
        info?.roomStatus = status
        if isViewLoaded {
            updateEnterRoomButtonTitle()
        }
    }
    
    func updateInfo(_ info: RoomBasicInfo) {
        self.info = info
        if isViewLoaded {
            applyCurrentInfoToView()
        }
    }
    
    func applyCurrentInfoToView() {
        updateViewWithCurrentStatus()
        updateAvailableActions()
        updateEnterRoomButtonTitle()
    }
    
    // MARK: - LifeCycle
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyCurrentInfoToView()
        loadData { [weak self] _ in
            guard let self = self else { return }
            self.applyCurrentInfoToView()
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
        observeRoomRemoved()
    }
    
    // MARK: - Private
    func loadData(completion: @escaping ((Result<RoomBasicInfo, ApiError>)->Void)) {
        guard let fetchingInfo = info else { return }
        RoomBasicInfo.fetchInfoBy(uuid: fetchingInfo.roomUUID, periodicUUID: fetchingInfo.periodicUUID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let detail):
                if self.info?.roomUUID == detail.roomUUID {
                    self.info = detail
                    completion(.success(detail))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    @objc func onRoomRemoved(_ notification: Notification) {
        guard
            let roomUUID = notification.userInfo?["roomUUID"] as? String,
            roomUUID == info?.roomUUID
        else { return }
        mainContainer?.removeTop()
    }
    
    func observeRoomRemoved() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.onRoomRemoved(_:)), name: .init(roomRemovedNotification), object: nil)
    }
    
    func updateAvailableActions() {
        guard let info = info else { return }
        let actions = info.roomActions(rootController: self)
        navigationItem.rightBarButtonItem = actions.isEmpty ? nil : UIBarButtonItem(image: UIImage(named: "cloud_file_more"),
                                                                                    style: .plain,
                                                                                    target: nil,
                                                                                    action: nil)
        navigationItem.rightBarButtonItem?.viewContainingControllerProvider = { [unowned self] in
            return self
        }
        navigationItem.rightBarButtonItem?.setupCommonCustomAlert(actions)
    }
    
    @IBAction func onClickCopy(_ sender: Any) {
        guard let info = info else { return }
        UIPasteboard.general.string = info.formatterInviteCode
        toast(localizeStrings("Copy Success"))
    }
    
    func setupViews() {
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
        guard let info = info else { return }
        if info.isOwner, info.roomStatus == .Idle {
            self.enterRoomButton.setTitle(localizeStrings("Start Class"), for: .normal)
        } else {
            self.enterRoomButton.setTitle(localizeStrings("Enter Room"), for: .normal)
        }
    }
    
    func updateViewWithCurrentStatus() {
        guard let info = info else { return }
        
        title = info.title
        
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
        statusLabel.textColor = status == .Started ? .color(type: .success) : .color(type: .text)
        
        roomNumberLabel.text = info.formatterInviteCode
        roomTypeLabel.text = NSLocalizedString(roomType.rawValue, comment: "")
        
        if status == .Stopped {
            replayButton.isHidden = info.hasRecord
            roomOperationStackView.arrangedSubviews.forEach {
                $0.isHidden = $0 === replayButton ? false : true
            }
        } else {
            replayButton.isHidden = true
            roomOperationStackView.arrangedSubviews.forEach {
                $0.isHidden = $0 === replayButton ? true : false
            }
        }
        
        roomOperationStackView.isHidden = hideAllActions
    }
    
    // MARK: - Action
    @IBAction func onClickReplay() {
        guard let info = info else { return }
        showActivityIndicator()
        ApiProvider.shared.request(fromApi: RecordDetailRequest(uuid: info.roomUUID)) { [weak self] result in
            guard let self = self else { return }
            self.stopActivityIndicator()
            switch result {
            case .success(let recordInfo):
                let viewModel = AdvanceReplayViewModel(roomInfo: info, recordDetail: recordInfo)
                let vc = AdvanceReplayViewController(viewModel: viewModel)
                self.mainContainer?.concreteViewController.present(vc, animated: true, completion: nil)
            case .failure(let error):
                self.toast(error.localizedDescription)
            }
        }
    }
    
    @IBAction func onClickInvite(_ sender: UIButton) {
        guard let info = info else { return }
        let vc = ShareManager.createShareActivityViewController(roomUUID: info.roomUUID,
                                                                beginTime: info.beginTime,
                                                                title: info.title,
                                                                roomNumber: info.inviteCode)
        popoverViewController(viewController: vc, fromSource: sender)
    }
    
    @IBAction func onClickEnterRoom(_ sender: Any) {
        guard let info = info else { return }
        enterRoomButton.isLoading = true
        // Join room
        RoomPlayInfo.fetchByJoinWith(uuid: info.roomUUID, periodicUUID: info.periodicUUID) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let playInfo):
                let deviceStatusStore = UserDevicePreferredStatusStore(userUUID: AuthStore.shared.user?.userUUID ?? "")
                let cameraOn = deviceStatusStore.getDevicePreferredStatus(.camera)
                let micOn = deviceStatusStore.getDevicePreferredStatus(.mic)
                let vc = ClassroomFactory.getClassRoomViewController(withPlayInfo: playInfo,
                                                                     detailInfo: info,
                                                                     deviceStatus: .init(mic: micOn, camera: cameraOn))
                self.mainContainer?.concreteViewController.present(vc, animated: true) {
                    self.enterRoomButton.isLoading = false
                }
            case .failure(let error):
                self.showAlertWith(message: error.localizedDescription)
                self.enterRoomButton.isLoading = false
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
