//
//  ClipItemCard.swift
//  Porta papeles
//
//  Created by Sulivan Antonety on 18/11/25.
//

import SwiftUI

struct ClipItemCard: View {
    let text: String
    let favicon: NSImage?
    let isLink: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            HStack {
                if isLink, let fav = favicon {
                    Image(nsImage: fav)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                }
                Text(preview.replacingOccurrences(of: "\n", with: " "))
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                
                Button(action: {}) {
                    Image(systemName: "star")
                        .foregroundColor(.yellow.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            
            Text(text)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.25))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        )
    }
    
    private var preview: String {
        text.components(separatedBy: .newlines).first ?? text
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
