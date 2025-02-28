//
//  ClassRoomFactory.swift
//  Flat
//
//  Created by xuyunshi on 2021/11/8.
//  Copyright © 2021 agora.io. All rights reserved.
//

import AgoraRtcKit
import Fastboard
import Foundation
import RxCocoa
import Whiteboard

enum ClassroomFactory {
    static func getClassRoomViewController(withPlayInfo playInfo: RoomPlayInfo,
                                           basicInfo: RoomBasicInfo,
                                           deviceStatus: DeviceState) -> ClassRoomViewController
    {
        // Config Rtc
        let rtc = Rtc(appId: Env().agoraAppId,
                      channelId: playInfo.roomUUID,
                      token: playInfo.rtcToken,
                      uid: playInfo.rtcUID,
                      communication: basicInfo.roomType == .oneToOne,
                      isFrontMirror: ClassroomDefaultConfig.frontCameraMirror,
                      isUsingFront: ClassroomDefaultConfig.usingFrontCamera,
                      screenShareInfo: playInfo.rtcShareScreen)

        FastRoom.followSystemPencilBehavior = ShortcutsManager.shared.shortcuts[.applePencilFollowSystem] ?? true
        let fastRoomConfiguration: FastRoomConfiguration
        let region: Region
        switch FlatRegion(rawValue: basicInfo.region) ?? .CN_HZ {
        case .CN_HZ:
            region = .CN
        case .US_SV:
            region = .US
        case .SG:
            region = .SG
        case .IN_MUM:
            region = .IN
        case .GB_LON:
            region = .GB
        case .none:
            region = .CN
        }
        let userName = AuthStore.shared.user?.name ?? ""

        fastRoomConfiguration = FastRoomConfiguration(appIdentifier: Env().netlessAppId,
                                                      roomUUID: playInfo.whiteboardRoomUUID,
                                                      roomToken: playInfo.whiteboardRoomToken,
                                                      region: region,
                                                      userUID: AuthStore.shared.user?.userUUID ?? "",
                                                      useFPA: userUseFPA,
                                                      userPayload: .init(nickName: userName),
                                                      audioMixerDelegate: rtc)

        if var ua = fastRoomConfiguration.whiteSdkConfiguration.value(forKey: "netlessUA") as? [String] {
            let env = Env()
            let isFlat = Bundle.main.bundleIdentifier == "io.agora.flat"
            let productName = env.name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: " ", with: "_")
            let str: String
            str = isFlat ? "FLAT/NETLESS_\(env.region)@\(env.version)" : "FLAT/\(productName)_\(env.region)@\(env.version)"
            ua.append(str)
            fastRoomConfiguration.whiteSdkConfiguration.setValue(ua, forKey: "netlessUA")
        }
        fastRoomConfiguration.whiteSdkConfiguration.enableSyncedStore = true
        fastRoomConfiguration.whiteSdkConfiguration.disableNewPencilStroke = !(ShortcutsManager.shared.shortcuts[.pencilTail] ?? true)
        let userPermissionEnable = basicInfo.isOwner
        fastRoomConfiguration.whiteRoomConfig.windowParams?.collectorStyles = ["top": "8px", "right": "8px"]
        fastRoomConfiguration.whiteRoomConfig.windowParams?.scrollVerticalOnly = true
        fastRoomConfiguration.whiteRoomConfig.windowParams?.stageStyle = "box-shadow: 0 0 0"
        fastRoomConfiguration.whiteRoomConfig.disableEraseImage = true
        fastRoomConfiguration.whiteRoomConfig.disableCameraTransform = !userPermissionEnable
        fastRoomConfiguration.whiteSdkConfiguration.log = false
        fastRoomConfiguration.whiteRoomConfig.isWritable = userPermissionEnable
        Fastboard.globalFastboardRatio = 1 / ClassRoomLayoutRatioConfig.whiteboardRatio
        let fastboardViewController = FastboardViewController(fastRoomConfiguration: fastRoomConfiguration)

        let camera = userPermissionEnable ? deviceStatus.camera : false
        let mic = userPermissionEnable ? deviceStatus.mic : false
        let initDeviceState = DeviceState(mic: mic, camera: camera)

        // Config Rtm
        let rtm = Rtm(rtmToken: playInfo.rtmToken,
                      rtmUserUUID: playInfo.rtmUID,
                      agoraAppId: Env().agoraAppId)
        let rtmChannel = rtm.joinChannelId(playInfo.rtmChannelId)
            .asObservable()
            .share(replay: 1, scope: .forever)
            .asSingle()

        // Config State imp
        let syncedStore = ClassRoomSyncedStore()
        let videoLayoutStore = VideoLayoutStoreImp()
        fastboardViewController.bindStore = syncedStore
        fastboardViewController.bindLayoutStore = videoLayoutStore

        let imp = ClassroomStateHandlerImp(syncedStore: syncedStore,
                                           rtm: rtm,
                                           commandChannelRequest: rtmChannel,
                                           roomUUID: playInfo.roomUUID,
                                           ownerUUID: playInfo.ownerUUID,
                                           userUUID: AuthStore.shared.user?.userUUID ?? "",
                                           isOwner: playInfo.rtmUID == playInfo.ownerUUID,
                                           maxWritableUsersCount: basicInfo.roomType.maxWritableUsersCount,
                                           roomStartStatus: basicInfo.roomStatus,
                                           whiteboardBannedAction: fastboardViewController.isRoomBanned.filter { $0 }.asObservable().mapToVoid(),
                                           whiteboardRoomError: fastboardViewController.roomError.asObservable(),
                                           rtcError: rtc.errorPublisher.asObservable())

        let isLocalUser: ((UInt) -> Bool) = { $0 == 0 || $0 == playInfo.rtcUID }
        let rtcViewModel = RtcViewModel(rtc: rtc,
                                        userRtcUid: playInfo.rtcUID,
                                        canUpdateLayout: basicInfo.isOwner,
                                        localUserRegular: isLocalUser,
                                        layoutStore: videoLayoutStore,
                                        userFetch: { rtcId -> RoomUser? in
                                            if rtcId == 0 { return imp.currentOnStageUsers[playInfo.rtmUID] }
                                            return imp.currentOnStageUsers.first(where: { $0.value.rtcUID == rtcId })?.value
                                        },
                                        userThumbnailStream: { rtcId -> AgoraVideoStreamType in
                                            guard let user = imp.currentOnStageUsers.first(where: { $0.value.rtcUID == rtcId })?.value else { return .low }
                                            let isTeacher = user.rtmUUID == playInfo.ownerUUID
                                            return playInfo.roomType.thumbnailStreamType(isUserTeacher: isTeacher)
            
        }, canUpdateDeviceState: { rtcUid in
            if isLocalUser(rtcUid) { return true }
            return basicInfo.isOwner
        })
        let rtcViewController = RtcViewController(viewModel: rtcViewModel)

        let alertProvider = DefaultAlertProvider()
        let vm = ClassRoomViewModel(stateHandler: imp,
                                    initDeviceState: initDeviceState,
                                    isOwner: basicInfo.isOwner,
                                    userUUID: playInfo.rtmUID,
                                    roomUUID: playInfo.roomUUID,
                                    roomType: basicInfo.roomType,
                                    commandChannelRequest: rtmChannel,
                                    rtm: rtm,
                                    alertProvider: alertProvider,
                                    preferredDeviceState: deviceStatus)

        let userListViewController = ClassRoomUsersViewController(userUUID: playInfo.rtmUID, roomOwnerRtmUUID: playInfo.ownerUUID)
        let shareViewController: () -> UIViewController = {
            let controller = InviteViewController(shareInfo: .init(roomDetail: basicInfo))
            controller.contentView.backgroundColor = .classroomChildBG
            controller.seperatorLine.backgroundColor = .classroomBorderColor
            return controller
        }
        let controller = ClassRoomViewController(viewModel: vm,
                                                 fastboardViewController: fastboardViewController,
                                                 rtcListViewController: rtcViewController,
                                                 userListViewController: userListViewController,
                                                 inviteViewController: shareViewController,
                                                 isOwner: basicInfo.isOwner,
                                                 ownerUUID: playInfo.ownerUUID,
                                                 beginTime: basicInfo.beginTime)
        alertProvider.root = controller
        logger.info("joined classroom \(playInfo.roomUUID), \(String(describing: initDeviceState))")
        return controller
    }
}
