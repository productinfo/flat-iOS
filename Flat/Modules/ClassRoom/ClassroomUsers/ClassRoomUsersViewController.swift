//
//  ClassRoomUsersViewController.swift
//  Flat
//
//  Created by xuyunshi on 2021/11/17.
//  Copyright © 2021 agora.io. All rights reserved.
//

import RxCocoa
import RxSwift
import UIKit

class ClassRoomUsersViewController: UIViewController {
    let cellIdentifier = "cellIdentifier"

    let userUUID: String
    let roomOwnerRtmUUID: String
    let isOwner: Bool

    let whiteboardTap: PublishRelay<RoomUser> = .init()
    let onStageTap: PublishRelay<RoomUser> = .init()
    let raiseHandTap: PublishRelay<RoomUser> = .init()
    let cameraTap: PublishRelay<RoomUser> = .init()
    let micTap: PublishRelay<RoomUser> = .init()
    let stopInteractingTap: PublishRelay<Void> = .init()

    var teacher: RoomUser? {
        didSet {
            tableView.reloadData()
        }
    }

    var users: Observable<[RoomUser]>? {
        didSet {
            guard let users else { return }

            let ownerId = roomOwnerRtmUUID
            let displayUsers = users
                .do(onNext: { [weak self] users in
                    self?.teacher = users.first(where: { $0.rtmUUID == ownerId })
                })
                .map { $0.filter { user in user.rtmUUID != ownerId } }
                .asDriver(onErrorJustReturn: [])

            let raiseHandUserCount = displayUsers.map { $0.filter(\.status.isRaisingHand).count }

            displayUsers
                .map { localizeStrings("Students") + " (\($0.count))" }
                .asDriver()
                .drive(studentCountLabel.rx.text)
                .disposed(by: rx.disposeBag)

            Driver.combineLatest(raiseHandUserCount, displayUsers.map(\.count))
                .map { localizeStrings("Raised Hand") + " (\($0)/\($1))" }
                .drive(raisedHandCountLabel.rx.text)
                .disposed(by: rx.disposeBag)

            displayUsers.drive(tableView.rx.items(cellIdentifier: cellIdentifier, cellType: RoomUserTableViewCell.self)) { [weak self] _, item, cell in
                self?.config(cell: cell, user: item)
            }
            .disposed(by: rx.disposeBag)

            if !isOwner {
                stopInteractingButton.isHidden = true
            } else {
                users.map {
                    $0.first(where: {
                        $0.rtmUUID != ownerId && ($0.status.isSpeak || $0.status.isRaisingHand)
                    }).map { _ in false } ?? true
                }.asDriver(onErrorJustReturn: true)
                    .drive(stopInteractingButton.rx.isHidden)
                    .disposed(by: rx.disposeBag)
            }
        }
    }

    // MARK: - LifeCycle

    init(userUUID: String,
         roomOwnerRtmUUID: String)
    {
        self.roomOwnerRtmUUID = roomOwnerRtmUUID
        self.userUUID = userUUID
        isOwner = roomOwnerRtmUUID == userUUID
        super.init(nibName: nil, bundle: nil)

        preferredContentSize = .init(width: greatWindowSide / 1.5, height: 560)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        bind()
    }

    // MARK: - Private

    func bind() {
        stopInteractingButton.rx.tap
            .bind(to: stopInteractingTap)
            .disposed(by: rx.disposeBag)

        tableView
            .rx.setDelegate(self)
            .disposed(by: rx.disposeBag)
    }

    func setupViews() {
        view.backgroundColor = .classroomChildBG
        view.addSubview(tableView)
        view.addSubview(topView)
        topView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(40)
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(topView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }
    }

    func config(cell: RoomUserTableViewCell, user: RoomUser) {
        cell.avatarImageView.kf.setImage(with: user.avatarURL)
        cell.nameLabel.text = user.name
        cell.cameraButton.isSelected = user.status.camera
        cell.micButton.isSelected = user.status.mic
        cell.statusLabel.text = nil
        cell.onStageSwitch.isOn = user.status.isSpeak
        cell.whiteboardSwitch.isOn = user.status.whiteboard
        cell.set(operationType: .mic, empty: !user.status.isSpeak)
        cell.set(operationType: .camera, empty: !user.status.isSpeak)
        cell.set(operationType: .raiseHand, empty: !user.status.isRaisingHand)
        if user.status.isSpeak, !user.isOnline {
            cell.statusLabel.text = "(\(localizeStrings("offline")))"
            cell.statusLabel.textColor = .systemRed
        }
        
        let isUserSelf = user.rtmUUID == userUUID
        if isOwner {
            cell.cameraButton.isEnabled = user.status.camera
            cell.micButton.isEnabled = user.status.mic
            cell.onStageSwitch.isEnabled = true
            cell.whiteboardSwitch.isEnabled = true
        } else {
            cell.cameraButton.isEnabled = isUserSelf
            cell.micButton.isEnabled = isUserSelf
            cell.onStageSwitch.isEnabled = user.status.isSpeak
            cell.whiteboardSwitch.isEnabled = user.status.whiteboard
        }
        cell.clickHandler = { [weak self] type in
            guard let self else { return }
            switch type {
            case .camera:
                self.cameraTap.accept(user)
            case .mic:
                self.micTap.accept(user)
            case .onStage:
                self.onStageTap.accept(user)
            case .whiteboard:
                self.whiteboardTap.accept(user)
            case .raiseHand:
                self.raiseHandTap.accept(user)
            }
        }
    }

    // MARK: - Lazy

    lazy var topView: UIView = {
        let view = UIView(frame: .zero)
        view.backgroundColor = .classroomChildBG
        let topLabel = UILabel(frame: .zero)
        topLabel.text = localizeStrings("User List")
        topLabel.textColor = .color(type: .text, .strong)
        topLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        view.addSubview(topLabel)
        topLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalToSuperview().inset(40)
        }

        let leftIcon = UIImageView()
        leftIcon.setTraitRelatedBlock { iconView in
            iconView.image = UIImage(named: "users")?.tintColor(.color(type: .text, .strong).resolvedColor(with: iconView.traitCollection))
        }
        leftIcon.contentMode = .scaleAspectFit
        view.addSubview(leftIcon)
        leftIcon.snp.makeConstraints { make in
            make.width.height.equalTo(24)
            make.centerY.equalToSuperview()
            make.left.equalToSuperview().inset(8)
        }
        view.addLine(direction: .bottom, color: .borderColor)
        return view
    }()

    lazy var teacherLabel: UILabel = {
        let label = UILabel()
        label.textColor = .color(type: .text)
        label.font = .systemFont(ofSize: 14)
        return label
    }()

    lazy var stopInteractingButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.titleLabel?.font = .systemFont(ofSize: 12)
        btn.setTitleColor(.color(type: .text), for: .normal)
        btn.setTitle(localizeStrings("Stop Interacting"), for: .normal)
        btn.contentEdgeInsets = .init(top: 12, left: 12, bottom: 12, right: 12)
        btn.layer.borderColor = UIColor.borderColor.cgColor
        btn.layer.borderWidth = commonBorderWidth
        return btn
    }()

    lazy var teachAvatarImageView: UIImageView = {
        let view = UIImageView()
        view.clipsToBounds = true
        view.contentMode = .scaleAspectFill
        view.layer.cornerRadius = 12
        return view
    }()

    lazy var teacherHeaderView: UITableViewHeaderFooterView = {
        let view = UITableViewHeaderFooterView()
        view.contentView.backgroundColor = .classroomChildBG
        view.addSubview(teachAvatarImageView)
        view.addSubview(teacherLabel)
        view.addSubview(stopInteractingButton)
        view.addSubview(headerItemStackView)
        teachAvatarImageView.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(16)
            make.top.equalToSuperview().inset(12)
            make.width.height.equalTo(24)
        }
        teacherLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().inset(48)
            make.centerY.equalTo(teachAvatarImageView)
            make.right.lessThanOrEqualTo(stopInteractingButton.snp.left).offset(-10)
        }
        stopInteractingButton.snp.makeConstraints { make in
            make.right.equalTo(view.safeAreaLayoutGuide).inset(12)
            make.centerY.equalTo(teachAvatarImageView)
            make.height.equalTo(28)
        }
        stopInteractingButton.layer.cornerRadius = 14

        headerItemStackView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(40)
        }
        return view
    }()

    func createHeaderItem(title: String) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .color(type: .text)
        label.text = title
        return label
    }

    lazy var studentCountLabel = createHeaderItem(title: localizeStrings("Students"))
    lazy var raisedHandCountLabel = createHeaderItem(title: localizeStrings("Students"))

    func insertSpacing(spacing: CGFloat, to stack: UIStackView) {
        if let first = stack.arrangedSubviews.first {
            stack.arrangedSubviews.dropFirst().forEach { i in
                i.snp.makeConstraints { make in
                    make.width.equalTo(first)
                }
            }
        }
        let indices = stack.arrangedSubviews.enumerated().map { i, _ in
            i + i
        }
        for i in indices {
            let v = UIView()
            stack.insertArrangedSubview(v, at: i)
            v.snp.makeConstraints { $0.width.equalTo(spacing) }
        }
    }

    lazy var headerItemStackView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [studentCountLabel,
                                                  createHeaderItem(title: localizeStrings("On/Off stage")),
                                                  createHeaderItem(title: localizeStrings("Whiteboard Permissions")),
                                                  createHeaderItem(title: localizeStrings("Camera")),
                                                  createHeaderItem(title: localizeStrings("Mic")),
                                                  raisedHandCountLabel])
        view.axis = .horizontal
        view.distribution = .fillProportionally
        view.backgroundColor = .color(type: .background, .strong)
        insertSpacing(spacing: 16, to: view)
        return view
    }()

    lazy var tableView: UITableView = {
        let view = UITableView(frame: .zero, style: .plain)
        view.backgroundColor = .classroomChildBG
        view.contentInsetAdjustmentBehavior = .never
        view.separatorStyle = .none
        view.register(RoomUserTableViewCell.self, forCellReuseIdentifier: cellIdentifier)
        view.rowHeight = 48
        if #available(iOS 15.0, *) {
            // F apple
            view.sectionHeaderTopPadding = 0
        } else {}
        return view
    }()
}

extension ClassRoomUsersViewController: UITableViewDelegate {
    func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        if let _ = teacher {
            return 88
        } else {
            return .leastNonzeroMagnitude
        }
    }

    func tableView(_: UITableView, viewForHeaderInSection _: Int) -> UIView? {
        if let teacher {
            teachAvatarImageView.kf.setImage(with: teacher.avatarURL)
            teacherLabel.text = localizeStrings("Teacher") + ": " + teacher.name
            return teacherHeaderView
        } else {
            return nil
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
