//
//  String+Extension.swift
//  FRTMTools
//
//  Created by PALOMBA VALENTINO on 09/09/25.
//


// String truncation helper (already defined, but good to have here)
extension String {
    func truncating(to length: Int, trailing: String = "...") -> String {
        if self.count > length {
            return trailing +  String(self.suffix(length))
        } else {
            return self
        }
    }
}
