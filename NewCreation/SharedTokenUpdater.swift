//
//  SharedTokenUpdater.swift
//  NewCreation
//
//  Created by Deep Bhupatkar on 07/03/25.
//


import Combine
import Foundation

@objc class SharedTokenUpdater: NSObject, ObservableObject {
    @Published var decodedTokens: [String] = []
    
    @objc static let shared = SharedTokenUpdater()
    
    @objc func addDecodedToken(_ token: String) {
        DispatchQueue.main.async {
            self.decodedTokens.append(token)
        }
    }

    @objc func clearTokens() {
        DispatchQueue.main.async {
            self.decodedTokens.removeAll()
        }
    }
}
