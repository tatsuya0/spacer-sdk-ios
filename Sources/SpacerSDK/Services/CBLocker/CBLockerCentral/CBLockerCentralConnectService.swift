//
//  CBLockerCentralConnectService.swift
//
//
//  Created by Takehito Soi on 2021/06/23.
//

import CoreBluetooth
import Foundation

class CBLockerCentralConnectService: NSObject {
    private var token: String!
    private var spacerId: String!
    private var action: CBLockerActionType!
    private var connectable: (CBLockerModel) -> Void = { _ in }
    private var success: () -> Void = {}
    private var failure: (SPRError) -> Void = { _ in }
    
    private var centralService: CBLockerCentralService?
    private var isCanceled = false

    override init() {
        NSLog("CBLockerCentralConnectService init")
        
        super.init()
        self.centralService = CBLockerCentralService(delegate: self)
    }
    
    private func scan() {
        NSLog("CBLockerCentralConnectService scan")
        
        centralService?.startScan()
    }
    
    func put(token: String, spacerId: String, success: @escaping () -> Void, failure: @escaping (SPRError) -> Void) {
        NSLog("CBLockerCentralConnectService put")
        
        self.token = token
        self.spacerId = spacerId
        self.action = .put
        self.connectable = { locker in self.connectWithRetry(locker: locker) }
        self.success = success
        self.failure = failure
        
        scan()
    }
    
    func take(token: String, spacerId: String, success: @escaping () -> Void, failure: @escaping (SPRError) -> Void) {
        NSLog("CBLockerCentralConnectService take")
        
        self.token = token
        self.spacerId = spacerId
        self.action = .take
        self.connectable = { locker in self.connectWithRetry(locker: locker) }
        self.success = success
        self.failure = failure
        
        scan()
    }
    
    private func connectWithRetry(locker: CBLockerModel, retryNum: Int = 0) {
        guard let peripheral = locker.peripheral else { return failure(SPRError.CBPeripheralNotFound) }
        
        NSLog("@@@@ connect peripheral retryNum:\(retryNum)")
        
        let peripheralDelegate =
            CBLockerPeripheralService.Factory.create(
                type: action, token: token, locker: locker, success: {
                    self.success()
                    self.disconnect(locker: locker)
                },
                failure: { error in
                    self.retryOrFailure(
                        error: error,
                        locker: locker,
                        retryNum: retryNum + 1,
                        executable: { self.connectWithRetry(locker: locker, retryNum: retryNum + 1) }
                    )
                }
            )
        
        guard let delegate = peripheralDelegate else { return failure(SPRError.CBConnectingFailed) }
        
        locker.peripheral?.delegate = delegate
        delegate.startConnectingAndDiscoveringServices()
        centralService?.connect(peripheral: peripheral)
    }
    
    private func retryOrFailure(error: SPRError, locker: CBLockerModel, retryNum: Int, executable: @escaping () -> Void) {
        NSLog("@@@@ retry or failure retryNum:\(retryNum), error: \(error.message)")
        
        if retryNum < CBLockerConst.MaxRetryNum {
            executable()
        } else {
            failure(error)
            disconnect(locker: locker)
        }
    }
    
    private func disconnect(locker: CBLockerModel) {
        guard let peripheral = locker.peripheral else { return failure(SPRError.CBPeripheralNotFound) }
        
        NSLog("CBLockerCentralConnectService disconnect")
        centralService?.disconnect(peripheral: peripheral)
    }
}

extension CBLockerCentralConnectService: CBLockerCentralDelegate {
    func execAfterDiscovered(locker: CBLockerModel) {
        
        NSLog("CBLockerCentralConnectService execAfterDiscovered")
        
        if locker.id == spacerId {
            centralService?.stopScan()
            successIfNotCanceled(locker: locker)
        }
    }
    
    func execAfterScanning(lockers: [CBLockerModel]) {
        
        NSLog("CBLockerCentralConnectService execAfterScanning")
        
        if centralService?.isScanning == true {
            centralService?.stopScan()
            failureIfNotCanceled(SPRError.CBCentralTimeout)
        }
    }
    
    func successIfNotCanceled(locker: CBLockerModel) {
        
        NSLog("CBLockerCentralConnectService successIfNotCanceled")
        
        centralService?.stopScan()
        
        if !isCanceled {
            isCanceled = true
            connectable(locker)
        }
    }

    func failureIfNotCanceled(_ error: SPRError) {
        
        NSLog("CBLockerCentralConnectService failureIfNotCanceled")
        
        centralService?.stopScan()
        
        if !isCanceled {
            isCanceled = true
            failure(error)
        }
    }
}
