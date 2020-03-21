//
//  main.swift
//  BluetoothTester
//
//  Created by Bjørn Inge Berg on 18/12/2019.
//  Copyright © 2019 Bjørn Inge Berg. All rights reserved.
//

import Foundation
import CoreBluetooth
import IOBluetooth
import Cocoa


print("Hello, World!")



class BluetoothEmulator: NSObject, CBPeripheralDelegate, CBPeripheralManagerDelegate {
    fileprivate let serviceUUIDs: [CBUUID] = [CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")]
    fileprivate lazy var primaryService = serviceUUIDs.first!
    fileprivate let writeCharachteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    fileprivate let notifyCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")


    fileprivate var writeCharacteristics  : CBMutableCharacteristic!
    fileprivate var notifyCharacteristics : CBMutableCharacteristic!

    private lazy var service: CBMutableService = CBMutableService(type: primaryService, primary: true)

    private var timer : RepeatingTimer?
    private var mtu : Int = 25
    var peripheralManager : CBPeripheralManager!


    private let managerQueue = DispatchQueue(label: "no.bjorninge.bluetoothManagerQueue", qos: .utility)

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("state: \(peripheral.stateDesc)")

        if peripheral.state == .poweredOn {
            startAdvertising()
        } else {
            stopAdvertising()
            print("bluetooth not on, aborting")
        }
    }



    func stopAdvertising() {
        print("stopping advertising")
        peripheralManager.stopAdvertising()
    }

    func startAdvertising() {



        if let deviceName = Host.current().localizedName {
           NSLog("Starting advertising on computer \(deviceName)")
        }

        guard let localName = IOBluetoothHostController().nameAsString(), localName.lowercased().starts(with: "bubble") else {
            fatalError("computer name must be changed to 'Bubble_fake' before running this program. Then restart bluetooth or computer to make it work!")
        }


        NSLog("Starting advertising with local name \(localName)")

        let advertisementData: [String : Any] = [
            CBAdvertisementDataLocalNameKey: localName,
            CBAdvertisementDataServiceUUIDsKey: [service.uuid],

            //CBAdvertisementDataSolicitedServiceUUIDsKey: [service.uuid]

        ]






        //peripheralManager.publishL2CAPChannel(withEncryption: false)
        peripheralManager.removeAllServices()
        peripheralManager.add(service)
        peripheralManager.startAdvertising(advertisementData)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        print("added service: \(service.description), error? \(error)")
    }

    override init() {


        super.init()

        let permissions: CBAttributePermissions = [.readable, .writeable]
        self.writeCharacteristics = CBMutableCharacteristic(type: writeCharachteristicUUID, properties: [.writeWithoutResponse, .write], value: nil, permissions: permissions)
        self.notifyCharacteristics = CBMutableCharacteristic(type: notifyCharacteristicUUID, properties: [.writeWithoutResponse, .write, .notify], value: nil, permissions: permissions)

        service.characteristics = [writeCharacteristics,notifyCharacteristics]

        NSLog("initing BluetoothEmulator")




        managerQueue.sync {
            peripheralManager = CBPeripheralManager(delegate: self, queue: managerQueue)
            peripheralManager.delegate = self
            print(peripheralManager.stateDesc)
        }




    }
    deinit {
        stopAdvertising()
        self.timer = nil
        peripheralManager = nil
        NSLog("deiniting BluetoothEmulator")

    }


    func periodicSendData(timeInterval: TimeInterval = 30) {
        NSLog("Setting periodic data transfer to : \(timeInterval) seconds")
        self.timer = RepeatingTimer(timeInterval: timeInterval)
        self.timer?.eventHandler = {
            NSLog("periodicSendSensorData Timer Fired")
            self.sendBubbleInfo()
            self.sendSerialNumber()
            self.sendSensorData()
        }
        self.timer?.resume()
    }


    func sendSerialNumber() {
        let serial = BubbleTx.formatSerialNumber()
        //peripheralManager.updateValue(serial, for: notifyCharacteristics, onSubscribedCentrals: nil)
        updateNotifyCharacteristicsInBatch(batches: [serial])

    }


    func sendSensorData(sensorData: SensorData = LibreOOPDefaults.TestPatchDataAlwaysReturning63 ) {

        NSLog("sendSensorData")
        let sequence = sensorData.bytes



        var batches = [Data]()

        //sensorData = SensorData(uuid: Data(rxBuffer.subdata(in: 5..<13)), bytes: [UInt8](rxBuffer.subdata(in: 18..<362)), date: Date())
        var advanceBy = mtu - BubbleTx.dataPacketPrefixLength

        for idx in stride(from: sequence.indices.lowerBound, to: sequence.indices.upperBound, by: advanceBy) {
            let subsequence = sequence[idx..<min(idx.advanced(by: advanceBy), sequence.count)]
            let data = BubbleTx.formatDataPacket(sequence: Array(subsequence), mtu: mtu)

            batches.append(data)


        }
        updateNotifyCharacteristicsInBatch(batches: batches)
        NSLog("completed sendSensorData")
        //self.notifyCharacteristics.value = data


    }

    func sendBubbleInfo() {
        var info = BubbleTx.formatBubbleInfo()
        peripheralManager.updateValue(info, for: notifyCharacteristics, onSubscribedCentrals: nil)


    }








    /*
     
 to support retransmit of large sets of data

     **/

    var sendingDataInfos = [Data]()
    let lockQueue = DispatchQueue(label: "com.test.LockQueue")


    func updateNotifyCharacteristicsInBatch(batches: [Data]) {
           // Change to your data
          for data in batches {
              lockQueue.sync() {
                  sendingDataInfos.append(data)
              }
          }
          processCharacteristicsUpdateQueue()
    }

    func updateCharacteristic(_ data: Data) -> Bool {
        peripheralManager.updateValue(data, for: notifyCharacteristics, onSubscribedCentrals: nil)
    }

    func processCharacteristicsUpdateQueue() {
          guard let characteristicData = sendingDataInfos.first else {
              return
          }
          while updateCharacteristic(characteristicData) {
              lockQueue.sync() {
                  _ = sendingDataInfos.remove(at: 0)
                  if sendingDataInfos.first == nil {
                      return
                  }
              }
          }
      }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
          processCharacteristicsUpdateQueue()
    }




}


extension BluetoothEmulator {


    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        print("peripheralManagerDidStartAdvertising")
        //stopAdvertising()

    }




    // Listen to dynamic values
    // Called when CBPeripheral .setNotifyValue(true, for: characteristic) is called from the central
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("\ndidSubscribeTo characteristic")
        mtu = central.maximumUpdateValueLength

    }
    // Read static values
    // Called when CBPeripheral .readValue(for: characteristic) is called from the central
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        print("\ndidReceiveRead request")


        peripheralManager.respond(to: request, withResult: .success)

    }


    /*
     dabear:: bubble responsestate is of type bubbleinfo
     dabear:: bubble responsestate is of type serialnumber
     dabear:: bubble responsestate is of type datapacket
     dabear:: bubble responsestate is of type datapacket..N

     **/


    // Called when receiving writing from Central.
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        print("\ndidReceiveWrite requests")
        guard let first = requests.first else {
            print("no request")
            return
        }
        
        requests.forEach{ req in


            NSLog("characteristic write request received for \(req.characteristic.uuid.uuidString)")
            NSLog("request value = \(req.value.debugDescription)")
            NSLog("request value decocced: \(req.value?.toDebugString())")

            //self.notifyCharacteristics.value = req.value
            if let value = req.value, let first = value.first {
                if value.count == 3 && first == 0x00 {
                    //var frequencyInterval = value[2]
                    //requestData, reset notifybuffer
                    NSLog("simulator: got requestdata request")

                    self.notifyCharacteristics.value = nil
                    sendBubbleInfo()


                } else if value.count == 6 && first == 0x02 {
                    //bubbleinfo ack with appid as value[5]
                    let appId = value[5]
                    NSLog("simulator: got bubbleinfo ack with appid \(appId)")
                    sendSerialNumber()
                    sendSensorData()
                    //periodicSendData()
                }
            }



        }

        peripheralManager.respond(to: first, withResult: .success)

    }



    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {

        timer = nil

        print("\ndidUnsubscribeFrom characteristic")


    }

    /*func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {

        print("willRestoreState")

    }*/

}
extension CBPeripheralManager {
    var stateDesc: String {
        switch self.state {
        case .poweredOff:
            return "poweredoff"

        case .poweredOn:
            return "poweredOn"
        case .resetting:
            return "resetting"
        case .unauthorized:
            return "unauthorized"
        case .unknown:
            return "unknown"
        case .unsupported:
            return "unsupported"
        }
    }
}

func runLoop() {
    var shouldKeepRunning = true
    let runLoop = RunLoop.current
    while shouldKeepRunning  &&
        runLoop.run(mode: .default, before: .distantFuture) {

    }
    print("OK, quitting")
}







BluetoothEmulator()

runLoop()

