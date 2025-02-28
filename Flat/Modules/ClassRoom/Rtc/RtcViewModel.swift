//
//  RtcViewModel.swift
//  Flat
//
//  Created by xuyunshi on 2021/11/29.
//  Copyright © 2021 agora.io. All rights reserved.
//

import AgoraRtcKit
import Foundation
import RxCocoa
import RxSwift

class RtcViewModel {
    internal init(rtc: Rtc,
                  userRtcUid: UInt,
                  canUpdateLayout: Bool,
                  localUserRegular: @escaping (UInt) -> Bool,
                  layoutStore: VideoLayoutStore,
                  userFetch: @escaping (UInt) -> RoomUser?,
                  userThumbnailStream: @escaping ((UInt) -> AgoraVideoStreamType),
                  canUpdateDeviceState: @escaping ((UInt) -> Bool))
    {
        self.canUpdateLayout = canUpdateLayout
        self.layoutStore = layoutStore
        self.rtc = rtc
        self.localUserRegular = localUserRegular
        self.userFetch = userFetch
        self.userThumbnailStream = userThumbnailStream
        self.userRtcUid = userRtcUid
        self.canUpdateDeviceState = canUpdateDeviceState
    }

    let canUpdateLayout: Bool
    let layoutStore: VideoLayoutStore
    let userRtcUid: UInt
    let rtc: Rtc
    let localUserRegular: (UInt) -> Bool
    let userFetch: (UInt) -> RoomUser?
    let userThumbnailStream: (UInt) -> AgoraVideoStreamType
    let canUpdateDeviceState: (UInt) -> Bool

    struct LayoutUsersInfo {
        let minimalUsers: [UInt]
        let expandUsers: [UInt]
        let freeDraggingUsers: [FreeDraggingUser]
    }

    struct LayoutInput {
        let users: Observable<[RoomUser]>
        let refreshTrigger: Driver<Void>
    }

    struct LayoutTaskInput {
        let userTap: Driver<UInt>
        let userDoubleTap: Driver<UInt>
        let userMinimalDragging: Driver<UInt>
        let userCanvasDragging: Driver<UserCanvasDraggingResult>
    }

    func updateStreamTypeWith(layoutInfo: LayoutUsersInfo) {
        guard rtc.isJoined.value else { return }
        let thumbNailInExpand = layoutInfo.expandUsers.count > 4
        layoutInfo
            .expandUsers
            .filter { !localUserRegular($0) }
            .forEach {
                if thumbNailInExpand {
                    rtc.updateRemoteUserStreamType(rtcUID: $0, type: userThumbnailStream($0))
                } else {
                    rtc.updateRemoteUserStreamType(rtcUID: $0, type: .high)
                }
            }
        
        layoutInfo
            .freeDraggingUsers
            .filter { !localUserRegular($0.uid) }
            .forEach {
                rtc.updateRemoteUserStreamType(rtcUID: $0.uid, type: .high)
            }
        
        layoutInfo
            .minimalUsers
            .filter { !localUserRegular($0) }
            .forEach {
                rtc.updateRemoteUserStreamType(rtcUID: $0, type: userThumbnailStream($0))
            }
    }

    func tranformLayoutTask(_ input: LayoutTaskInput) -> Observable<UInt> {
        func sortUsersZIndex(_ users: [DraggingUser]) -> [DraggingUser] {
            users
                .sorted(by: { $0.z < $1.z })
                .enumerated()
                .map { index, i in
                    var j = i
                    j.z = index
                    return j
                }
        }

        let layoutState = layoutStore
            .layoutState()

        let doubleTapTask = input
            .userDoubleTap
            .asObservable()
            .withLatestFrom(layoutState) { [unowned self] uid, state -> UInt in
                guard let uuid = self.userFetch(uid)?.rtmUUID else { return uid }
                if state.gridUsers.isEmpty {
                    var gridUsers = state.freeDraggingUsers.map(\.uuid) // Add free view
                    gridUsers.append(uuid) // Add current
                    self.layoutStore.updateExpandUsers(gridUsers.removeDuplicate())
                } else {
                    if state.gridUsers.contains(uuid) { // Dismiss expand
                        self.layoutStore.updateExpandUsers([])
                    } else { // Add new to expand
                        var gridUsers = state.gridUsers
                        gridUsers.append(uuid) // Add current
                        self.layoutStore.updateExpandUsers(gridUsers.removeDuplicate())
                    }
                }
                return uid
            }

        let tapTask = input
            .userTap
            .asObservable()
            .withLatestFrom(layoutState) { [unowned self] uid, state -> UInt in
                guard let uuid = self.userFetch(uid)?.rtmUUID else { return uid }
                var freeUsers = state.freeDraggingUsers
                if let index = freeUsers.firstIndex(where: { $0.uuid == uuid }) {
                    var user = freeUsers[index]
                    let targetIndex = (freeUsers.map(\.z).max() ?? 0) + 1
                    user.z = targetIndex
                    freeUsers[index] = user
                    self.layoutStore.updateFreeDraggingUsers(sortUsersZIndex(freeUsers))
                }
                return uid
            }

        let minimalDragTask = input.userMinimalDragging
            .asObservable()
            .withLatestFrom(layoutState) { [unowned self] uid, state -> UInt in
                guard let uuid = self.userFetch(uid)?.rtmUUID else { return uid }
                if state.gridUsers.contains(uuid) {
                    let gridUsers = state.gridUsers.filter { $0 != uuid }
                    self.layoutStore.updateExpandUsers(gridUsers.removeDuplicate())
                }
                self.layoutStore.removeFreeDraggingUsers([uuid])
                return uid
            }

        let canvasDragTask = input.userCanvasDragging
            .asObservable()
            .withLatestFrom(layoutState) { drag, state in
                let (uid, rect) = drag
                guard let uuid = self.userFetch(uid)?.rtmUUID else { return uid }
                if !state.gridUsers.isEmpty {
                    var gridUsers = state.gridUsers
                    gridUsers.append(uuid)
                    self.layoutStore.updateExpandUsers(gridUsers.removeDuplicate())
                } else {
                    var freeUsers = state.freeDraggingUsers
                    let targetIndex = (freeUsers.map(\.z).max() ?? 0) + 1
                    let user = DraggingUser(uuid: uuid,
                                            x: rect.origin.x,
                                            y: rect.origin.y,
                                            z: targetIndex,
                                            width: rect.width,
                                            height: rect.height)
                    if let index = state.freeDraggingUsers.firstIndex(where: { $0.uuid == uuid }) {
                        freeUsers[index] = user
                    } else {
                        freeUsers.append(user)
                    }
                    self.layoutStore.updateFreeDraggingUsers(sortUsersZIndex(freeUsers))
                }
                return drag.uid
            }

        return .merge(tapTask, doubleTapTask, minimalDragTask, canvasDragTask)
    }

    func tranformLayoutInfo(_ input: LayoutInput) -> Observable<LayoutUsersInfo> {
        let layoutState = layoutStore
            .layoutState()

        let vcTrigger = input
            .refreshTrigger
            .asObservable()
            .withLatestFrom(layoutState)
        let dataTrigger = layoutState

        let trigger = Observable.merge(vcTrigger, dataTrigger)

        let userInfo = Observable.combineLatest(trigger, input.users) { state, users -> LayoutUsersInfo in
            let gridUsers = state.gridUsers.compactMap { gu -> UInt? in
                users.first(where: { $0.rtmUUID == gu })?.rtcUID
            }
            let sorted = state.freeDraggingUsers
                .sorted(by: { $0.z < $1.z }) // Sort index
            let freeDraggingUsers = sorted
                .compactMap { ds -> FreeDraggingUser? in
                    if let user = users.first(where: { $0.rtmUUID == ds.uuid }) { // Filter grid users.
                        if gridUsers.contains(user.rtcUID) {
                            return nil
                        }
                        return .init(uid: user.rtcUID, rect: .init(x: ds.x, y: ds.y, width: ds.width, height: ds.height))
                    }
                    return nil
                }
            let minimalUsers = users.filter { u in
                if gridUsers.contains(u.rtcUID) { return false }
                if freeDraggingUsers.contains(where: { $0.uid == u.rtcUID }) { return false }
                return true
            }.map(\.rtcUID)
            return .init(minimalUsers: minimalUsers,
                         expandUsers: gridUsers,
                         freeDraggingUsers: freeDraggingUsers)
        }
        .debounce(.milliseconds(100), scheduler: MainScheduler.instance) // To avoid multi data change times in a short time.
        .do(onNext: { [weak self] layout in
            self?.updateStreamTypeWith(layoutInfo: layout)
        })
        return userInfo
    }

    lazy var videoCanvasViews: [UInt: AgoraCanvasContainer] = [:]
    func setupRtcVideo(canvas: AgoraRtcVideoCanvas, isLocal: Bool) -> AgoraCanvasContainer {
        let uid = canvas.uid
        if let v = videoCanvasViews[uid] {
            return v
        }
        let newView = AgoraCanvasContainer()
        videoCanvasViews[uid] = newView
        canvas.view = newView
        if isLocal {
            rtc.agoraKit.setupLocalVideo(canvas)
        } else {
            rtc.agoraKit.setupRemoteVideo(canvas)
        }
        return newView
    }

    func canvasView(for UID: UInt) -> AgoraCanvasContainer {
        let isLocal = localUserRegular(UID)
        let canvas = (isLocal ? rtc.localVideoCanvas : rtc.createOrFetchFromCacheCanvas(for: UID))!
        let canvasView = setupRtcVideo(canvas: canvas, isLocal: isLocal)
        return canvasView
    }

    // process remote user status
    struct RTCUserOutput {
        let user: RoomUser
        let canvasView: AgoraCanvasContainer
    }

    func trans(_ us: Driver<[RoomUser]>) -> Driver<[RTCUserOutput]> {
        us.map { [weak self] users -> [RTCUserOutput] in
            guard let self else { return [] }
            return users.map { user -> RTCUserOutput in
                let isLocal = self.localUserRegular(user.rtcUID)
                let cv = self.canvasView(for: user.rtcUID)
                if isLocal {
                    self.rtc.updateLocalUser(micOn: user.status.mic)
                    self.rtc.updateLocalUser(cameraOn: user.status.camera)
                } else {
                    self.rtc.updateRemoteUser(rtcUID: user.rtcUID, cameraOn: user.status.camera, micOn: user.status.mic)
                }
                return .init(user: user, canvasView: cv)
            }
        }
    }

    func strenthFor(uid: UInt) -> Observable<CGFloat> {
        let uid = uid == userRtcUid ? 0 : uid
        if let s = rtc.micStrenths[uid] {
            return s.asObservable()
        } else {
            rtc.micStrenths[uid] = .init()
            return strenthFor(uid: uid)
        }
    }
}
