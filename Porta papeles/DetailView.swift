//
//  DetailView.swift
//  Porta papeles
//
//  Created by Sulivan Antonety on 18/11/25.
//

import SwiftUI

struct DetailView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Detalle")
    }
}
