//
//  DependencyRegister.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 05/09/25.
//

import Foundation
import FRTMCore

final class DependencyRegister {
    
    static func register() {
        
        CoreDependencyContainer.shared
            .registerSingleton(PersistenceManager.self) {
                CorePersistenceManager()
            }
        
        CoreDependencyContainer.shared
            .registerSingleton(Analyzer.self) {
                IPAAnalyzer()
            }
    }
}
