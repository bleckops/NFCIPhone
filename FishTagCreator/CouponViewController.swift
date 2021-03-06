/*
See LICENSE folder for this sample’s licensing information.

Abstract:
View controller that creates coupon tag.
*/

import UIKit
import CoreNFC

class CouponViewController: UITableViewController, NFCTagReaderSessionDelegate {

    // MARK: - Properties
    var readerSession: NFCTagReaderSession?
    var couponCode: String = String()
    
    // MARK: - Actions
    @IBAction func createCoupon(_ sender: UIButton) {
        guard NFCNDEFReaderSession.readingAvailable else {
            let alertController = UIAlertController(
                title: "Scanning Not Supported",
                message: "This device doesn't support tag scanning.",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true, completion: nil)
            return
        }
        
        guard let couponString = sender.restorationIdentifier else {
            return
        }
        
        couponCode = "FISH" + couponString
        
        readerSession = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        readerSession?.alertMessage = "Hold your iPhone near an NFC Type 2 tag."
        readerSession?.begin()
    }
    
    // MARK: - Private helper functions
    func write(_ data: Data, to tag: NFCMiFareTag, offset: UInt8) {
        // These properties prepare a T2T write command to write a 4 byte block at a specific block offset.
        let writeBlockCommand: UInt8 = 0xA2
        let successCode: UInt8 = 0x0A
        let blockSize = 4
        var blockData: Data = data.prefix(blockSize)
        
        // You need to zero-pad the data to fill the block size.
        if blockData.count < blockSize {
            blockData += Data(count: blockSize - blockData.count)
        }
        
        let writeCommand = Data([writeBlockCommand, offset]) + blockData
        if #available(iOS 14.0, *) {
            tag.sendMiFareCommand(commandPacket: writeCommand) { (result: Result<Data, Error>) in
                switch result {
                case .success(let response):
                    if response[0] != successCode {
                        self.readerSession?.invalidate(errorMessage: "Write tag error. Please try again.")
                        return
                    }
                    
                    let newSize = data.count - blockSize
                    if newSize > 0 {
                        self.write(data.suffix(newSize), to: tag, offset: (offset + 1))
                    } else {
                        self.readerSession?.alertMessage = "Coupon is written."
                        self.readerSession?.invalidate()
                    }
                case .failure(let error):
                    self.readerSession?.invalidate(errorMessage: "Write tag error: \(error.localizedDescription). Please try again.")
                }
            }
        } else {
            tag.sendMiFareCommand(commandPacket: writeCommand) { (response: Data, error: Error?) in
                if error != nil {
                    self.readerSession?.invalidate(errorMessage: "Write tag error. Please try again.")
                    return
                }
                
                if response[0] != successCode {
                    self.readerSession?.invalidate(errorMessage: "Write tag error. Please try again.")
                    return
                }
                
                let newSize = data.count - blockSize
                if newSize > 0 {
                    self.write(data.suffix(newSize), to: tag, offset: (offset + 1))
                } else {
                    self.readerSession?.alertMessage = "Coupon is written."
                    self.readerSession?.invalidate()
                }
            }
        }
    }
    
    func writeCouponCode(from mifareTag: NFCMiFareTag) {
//        guard case let .miFare(mifareTag) = tag else {
//            return
//        }
        
        DispatchQueue.global().async {
            
            // Block size of T2T tag is 4 bytes. Coupon code is stored starting
            // at block 04. Assume the maximum coupon code length is 16 bytes.
            // Coupon code data structure is as follow:
            // Block 04 => Header of the coupon. 2 bytes magic signature + 1 byte use counter + 1 byte length field.
            // Block 05 => Start of coupon code. Continues as indicated by the length field.
            
            let dataOffset: UInt8 = 4
            let magicSignature: [UInt8] = [0xFE, 0x01]
            let useCount: UInt8 = 0x1
            let couponData = self.couponCode.data(using: .ascii)!
            
            let data = Data(magicSignature + [useCount, UInt8(couponData.count)]) + couponData

            self.write(data, to: mifareTag, offset: dataOffset)
        }
    }
    
    // MARK: - NFCTagReaderSessionDelegate
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // If necessary, you may perform additional operations on session start.
        // At this point RF polling is enabled.
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        // If necessary, you may handle the error. Note session is no longer valid.
        // You must create a new session to restart RF polling.
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        var tag: NFCTag? = nil
        
        for nfcTag in tags {
            // In this example you are searching for a MIFARE Ultralight tag (NFC Forum T2T tag platform).
            if case let .miFare(mifareTag) = nfcTag {
                if mifareTag.mifareFamily == .ultralight {
                    tag = nfcTag
                    break
                }
            }
        }
        
        if tag == nil {
            session.invalidate(errorMessage: "No valid tag found.")
            return
        }
        
        session.connect(to: tag!) { (error: Error?) in
            if error != nil {
                session.invalidate(errorMessage: "Connection error. Please try again.")
                return
            }
            //self.writeCouponCode(from: tag!)
            self.miFareTagProcessBlockPssw(tag: tag!)
        }
    }    
    
    func miFareTagProcessBlockPssw(tag: NFCTag){
        
        guard case let .miFare(mifareTag) = tag else {
            return
        }
        DispatchQueue.global().async {
            self.pwdCommand(tag: mifareTag)
            //self.miFareTagProcessAuth(tag: mifareTag)
        }
    }
    
    func readTestCommand(tag: NFCMiFareTag){
        let dataRead: [UInt8] = [0x30, 0x04] // Read E3 AUTH
        let dataReadPacket = Data(dataRead)
        
        tag.sendMiFareCommand(commandPacket: dataReadPacket) { (result: Result<Data, Error>) in
            switch result {
            case .success(let response):
                print("READ AUTH")
            case .failure(let error):
                self.readerSession?.invalidate(errorMessage: "ERROR READ AUTH")
                return
            }
        }
    }
    
    func miFareTagProcessAuth(tag: NFCMiFareTag){
        
        let dataAuth: [UInt8] = [0x1B, 0xFF, 0xFF, 0xFF, 0xFF] // PWD_AUTH 1B PSSW 0xFFFFFFFF
        let dataAuthPacket = Data(dataAuth)
        
        tag.sendMiFareCommand(commandPacket: dataAuthPacket) { (result: Result<Data, Error>) in
            switch result {
            case .success(let response):
                print("WRITE AUTH")
                self.pwdCommand(tag: tag)
            case .failure(let error):
                self.readerSession?.invalidate(errorMessage: "ERROR AUTH PWD")
                return
            }
        }
    }
    
    func pwdCommand(tag: NFCMiFareTag){
        let dataPwd: [UInt8] = [0xA2, 0x85, 0xFF, 0xFF, 0xFF, 0xFF] // Write 85 PSSW 0xFFFFFFFF
        let dataPwdPacket = Data(dataPwd)
        
        tag.sendMiFareCommand(commandPacket: dataPwdPacket) { (result: Result<Data, Error>) in
            switch result {
            case .success(let response):
                print("WRITE PWD")
                self.packCommand(tag: tag)
            case .failure(let error):
                self.readerSession?.invalidate(errorMessage: "ERROR WRITE PWD")
                return
            }
        }
    }
    
    func packCommand(tag: NFCMiFareTag){
        //Pack is the aknowledge code that NFC card return when user correctly authenticates
        let dataPack: [UInt8] = [0xA2, 0x86, 0x01, 0x02, 0x00, 0x00] // Write 86 PACK 0x0102
        let dataPackPacket = Data(dataPack)
        
        tag.sendMiFareCommand(commandPacket: dataPackPacket) { (result: Result<Data, Error>) in
            switch result {
            case .success(let response):
                print("WRITE PACK")
                self.authCommand(tag: tag)
            case .failure(let error):
                self.readerSession?.invalidate(errorMessage: "ERROR WRITE PACK")
                return
            }
        }
    }
    
    func protCommand(tag: NFCMiFareTag){
        let dataProt: [UInt8] = [0x30, 0x84, 0x08, 0x00, 0x00, 0x00] // Write PROT to 1
        let dataProtPacket = Data(dataProt)
        
        tag.sendMiFareCommand(commandPacket: dataProtPacket) { (result: Result<Data, Error>) in
            switch result {
            case .success(let response):
                print("WRITE PROT")
                self.authCommand(tag: tag)
            case .failure(let error):
                self.readerSession?.invalidate(errorMessage: "ERROR WRITE PROT")
                return
            }
        }
    }
    
    func authCommand(tag: NFCMiFareTag){
        let dataRead: [UInt8] = [0x30, 0x83] // Read 83 to get AUTH0 conf
        let dataReadPacket = Data(dataRead)
        
        tag.sendMiFareCommand(commandPacket: dataReadPacket) { (result: Result<Data, Error>) in
            switch result {
            case .success(let response):
                print("READ AUTH0")
                let dataByte : [UInt8] = [UInt8](response)
                if dataByte.count > 2{
                    let byte1 = dataByte[0], byte2 = dataByte[1], byte3 = dataByte[2]
                    let dataAuth: [UInt8] = [0xA2, 0x83, byte1, byte2, byte3, 0x04] // Write 83 AUTH0 on loc on 0x04
                    let dataAuthPacket = Data(dataAuth)
                    tag.sendMiFareCommand(commandPacket: dataAuthPacket) { (result: Result<Data, Error>) in
                        switch result {
                        case .success(let response):
                            print("WRITE AUTH0")
                            self.writeCouponCode(from: tag)
                        case .failure(let error):
                            self.readerSession?.invalidate(errorMessage: "ERROR READ AUTH0")
                            return
                        }
                    }
                }
            case .failure(let error):
                self.readerSession?.invalidate(errorMessage: "ERROR READ AUTH0")
                return
            }
        }
                
    }
    
}
