//
//  ClassroomCoordinator.swift
//  Flat
//
//  Created by xuyunshi on 2023/1/10.
//  Copyright © 2023 agora.io. All rights reserved.
//

import Foundation
import RxSwift

class ClassroomCoordinator: NSObject {
    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onClassroomLeaving),
                                               name: classRoomLeavingNotificationName,
                                               object: nil)
    }

    static let shared = ClassroomCoordinator()

    var currentClassroomUUID: String?
    var enterClassDate: Date?

    @objc func onClassroomLeaving() {
        // Just remove all the info for can't get the leaving scene identifier.
        currentClassroomUUID = nil
        if let enterClassDate {
            let duration = Date().timeIntervalSince(enterClassDate)
            if #available(iOS 14.0, *) {
                RatingManager.requestReviewIfAppropriate(context: .init(enterClassroomDuration: duration))
            }
            self.enterClassDate = nil
        }
    }
    
    func enterClassroomFrom(windowScene: UIWindowScene) {
        guard let uuid = windowScene.session.userInfo?["roomUUID"] as? String
        else { return }
        currentClassroomUUID = uuid
        enterClassDate = Date()
        let periodicUUID = windowScene.session.userInfo?["periodicUUID"] as? String
        let window = windowScene.windows.first(where: \.isKeyWindow)
        let emptyRoot = EmptySplitSecondaryViewController()
        window?.rootViewController = emptyRoot
        emptyRoot.showActivityIndicator()
        fetchClassroomViewController(uuid: uuid,
                                     periodUUID: periodicUUID,
                                     basicInfo: nil)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self) { _, vc in
                emptyRoot.stopActivityIndicator()
                window?.rootViewController = vc
            } onFailure: { weakSelf, error in
                emptyRoot.stopActivityIndicator()
                weakSelf.currentClassroomUUID = nil
                emptyRoot.showAlertWith(message: localizeStrings("JoinRoomFailWarning") + " : \(error.localizedDescription)") {
                    UIApplication.shared.requestSceneSessionDestruction(windowScene.session,
                                                                        options: nil)
                }
            }
            .disposed(by: rx.disposeBag)
    }

    func enterClassroom(uuid: String,
                        periodUUID: String?,
                        basicInfo: RoomBasicInfo?,
                        sender: UIResponder?)
    {
        // Prevent join two classroom one time.
        let controller = sender?.viewController()
        if currentClassroomUUID != nil {
            controller?.toast(localizeStrings("ExitCurrentClassroomWarning"))
            return
        }

        currentClassroomUUID = uuid
        enterClassDate = Date()
        if #available(iOS 14.0, *) {
            if ProcessInfo().isiOSAppOnMac {
                guard let main = controller?.mainContainer?.concreteViewController else { return }
                if let _ = main.presentedViewController { main.dismiss(animated: true) }
                // M1 Mac
                let userActivety = NSUserActivity(activityType: NSUserActivity.Classroom)
                userActivety.userInfo?["roomUUID"] = uuid
                userActivety.userInfo?["periodicUUID"] = periodUUID
                let options = UIScene.ActivationRequestOptions()
                options.requestingScene = sender?.scene()
                UIApplication.shared.requestSceneSessionActivation(nil,
                                                                   userActivity: userActivety,
                                                                   options: options)
                return
            }
        }
        // iOS or iPad
        let btn = sender as? UIButton
        btn?.isLoading = true

        fetchClassroomViewController(uuid: uuid,
                                     periodUUID: periodUUID,
                                     basicInfo: basicInfo)
            .observe(on: MainScheduler.instance)
            .subscribe(with: self, onSuccess: { _, vc in
                btn?.isLoading = false

                guard let main = controller?.mainContainer?.concreteViewController else { return }
                if let _ = main.presentedViewController {
                    main.showActivityIndicator()
                    main.dismiss(animated: true) {
                        main.stopActivityIndicator()
                        main.present(vc, animated: true)
                    }
                } else {
                    main.present(vc, animated: true)
                }
            }, onFailure: { weakSelf, error in
                btn?.isLoading = false
                weakSelf.currentClassroomUUID = nil
                controller?.showAlertWith(message: error.localizedDescription)
            })
            .disposed(by: rx.disposeBag)
    }

    private func fetchClassroomViewController(uuid: String,
                                              periodUUID: String?,
                                              basicInfo: RoomBasicInfo?) -> Single<ClassRoomViewController>
    {
        guard let user = AuthStore.shared.user else { return .error("user not login") }
        let deviceStatusStore = UserDevicePreferredStatusStore(userUUID: user.userUUID)
        let micOn = deviceStatusStore.getDevicePreferredStatus(.mic)
        let cameraOn = deviceStatusStore.getDevicePreferredStatus(.camera)
        let deviceState = DeviceState(mic: micOn, camera: cameraOn)
        return RoomPlayInfo.fetchByJoinWith(uuid: uuid, periodicUUID: periodUUID)
            .concatMap { p -> Observable<(RoomPlayInfo, RoomBasicInfo)> in
                if let basicInfo {
                    return .just((p, basicInfo))
                } else {
                    return RoomBasicInfo.fetchInfoBy(uuid: p.roomUUID, periodicUUID: periodUUID)
                        .map { (p, $0) }
                }
            }
            .map { ClassroomFactory.getClassRoomViewController(withPlayInfo: $0.0, basicInfo: $0.1, deviceStatus: deviceState) }
            .asSingle()
    }
}
