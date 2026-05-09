import SwiftUI

struct CellPopupView: View {
    @EnvironmentObject var popupModel: PopupModel
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        if let cell = popupModel.activeCell {
            ZStack {
                // 1. The Main Popup
                ZStack(alignment: .topTrailing) {
                    PhoneticCellView(
                        cell: cell,
                        isShowingIPA: true,
                        ipaFontSize: 16.0,
                        cellWidth: 100,
                        isPopup: true
                    )
                    .padding(.top, 16)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .background(Color.primary.opacity(0.04))
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                .scaleEffect(2.0)
                .position(
                    x: popupModel.position.x + dragOffset.width,
                    y: popupModel.position.y + dragOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            popupModel.position.x += value.translation.width
                            popupModel.position.y += value.translation.height
                            dragOffset = .zero
                        }
                )
                .onTapGesture {
                    closePopup()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
                .background(
                    Group {
                        Button("") { popupModel.navigate(dx: -1, dy: 0) }.keyboardShortcut(.leftArrow, modifiers: [])
                        Button("") { popupModel.navigate(dx: 1, dy: 0) }.keyboardShortcut(.rightArrow, modifiers: [])
                        Button("") { popupModel.navigate(dx: 0, dy: -1) }.keyboardShortcut(.upArrow, modifiers: [])
                        Button("") { popupModel.navigate(dx: 0, dy: 1) }.keyboardShortcut(.downArrow, modifiers: [])
                        Button("") { popupModel.navigateToExtreme(isFirst: true) }.keyboardShortcut(.leftArrow, modifiers: [.command])
                        Button("") { popupModel.navigateToExtreme(isFirst: false) }.keyboardShortcut(.rightArrow, modifiers: [.command])
                    }
                    .opacity(0)
                )
                
                // 2. The Navigation Toolbar
                VStack {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button(action: { popupModel.navigateToExtreme(isFirst: true) }) {
                            VStack {
                                Image(systemName: "arrow.backward.to.line")
                                    .font(.system(size: 32))
                                Text("First")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: -1, dy: 0) }) {
                            VStack {
                                Image(systemName: "arrow.left.square.fill")
                                    .font(.system(size: 32))
                                Text("Left")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: 0, dy: -1) }) {
                            VStack {
                                Image(systemName: "arrow.up.square.fill")
                                    .font(.system(size: 32))
                                Text("Up")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: 0, dy: 1) }) {
                            VStack {
                                Image(systemName: "arrow.down.square.fill")
                                    .font(.system(size: 32))
                                Text("Down")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(action: { popupModel.navigate(dx: 1, dy: 0) }) {
                            VStack {
                                Image(systemName: "arrow.right.square.fill")
                                    .font(.system(size: 32))
                                Text("Right")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { popupModel.navigateToExtreme(isFirst: false) }) {
                            VStack {
                                Image(systemName: "arrow.forward.to.line")
                                    .font(.system(size: 32))
                                Text("Last")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .frame(height: 32)
                            .padding(.horizontal, 4)
                        
                        Button(action: { closePopup() }) {
                            VStack {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 32))
                                Text("Close")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.bottom, 24)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func closePopup() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            popupModel.activeCell = nil
        }
    }
}
