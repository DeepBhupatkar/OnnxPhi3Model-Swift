//
//  ContentView.swift
//  NewCreation
//
//  Created by Deep Bhupatkar on 07/03/25.
//

import SwiftUI
import Speech
import Darwin
import Darwin.POSIX
import Darwin.C

// Add these constants at the top of the file, after imports
private let THREAD_BASIC_INFO_COUNT = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)

struct Message: Identifiable, Equatable {
    let id = UUID()
    var text: String
    let isUser: Bool
    
    // Implement Equatable
    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id && 
               lhs.text == rhs.text && 
               lhs.isUser == rhs.isUser
    }
}

struct SystemStats {
    var cpuUsage: Double
    var memoryUsage: Double
    var totalMemory: UInt64
    
    static func getCurrentStats() -> SystemStats {
        // Get App's Process Info
        let processInfo = ProcessInfo.processInfo
        let pid = processInfo.processIdentifier
        
        // Get Task Memory Info
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), pointer, &count)
            }
        }
        
        // Calculate Memory Usage
        var memoryUsage: Double = 0
        let totalMemory = processInfo.physicalMemory
        if result == KERN_SUCCESS {
            let usedMemory = UInt64(taskInfo.phys_footprint)
            memoryUsage = (Double(usedMemory) / Double(totalMemory)) * 100.0
        }
        
        // Get CPU Usage
        var cpuUsage: Double = 0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let threadResult = task_threads(mach_task_self_, &threadList, &threadCount)
        if threadResult == KERN_SUCCESS, let threadList = threadList {
            for i in 0..<Int(threadCount) {
                var threadInfo = thread_basic_info()
                var count = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) { pointer in
                    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                        thread_info(threadList[i], thread_flavor_t(THREAD_BASIC_INFO), pointer, &count)
                    }
                }
                
                if infoResult == KERN_SUCCESS {
                    let timeDelta = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    cpuUsage += timeDelta
                }
            }
            
            // Deallocate the thread list
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threadList), 
                         vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.stride))
        }
        
        return SystemStats(
            cpuUsage: min(cpuUsage, 100.0), // Cap at 100%
            memoryUsage: memoryUsage,
            totalMemory: totalMemory
        )
    }
}

struct SystemStatsView: View {
    @State private var stats = SystemStats(cpuUsage: 0, memoryUsage: 0, totalMemory: 0)
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resource Monitor")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 6) {
                StatRow(title: "CPU", value: stats.cpuUsage, unit: "%")
                StatRow(title: "RAM", value: stats.memoryUsage, unit: "%")
                Text(formatMemory(UInt64(stats.memoryUsage * Double(stats.totalMemory) / 100.0)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .onReceive(timer) { _ in
            stats = SystemStats.getCurrentStats()
        }
    }
    
    private func formatMemory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        return String(format: "%.1f MB", megabytes)
    }
}

struct StatRow: View {
    let title: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.1f%@", value, unit))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    // Progress bar
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .cyan]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(min(value, 100) / 100))
                        .frame(height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
    }
}

struct ContentView: View {
    @State private var userInput: String = ""
    @State private var messages: [Message] = []
    @State private var isGenerating: Bool = false
    @State private var stats: String = ""
    @State private var showAlert: Bool = false
    @State private var errorMessage: String = ""

    private let generator = GenAIGenerator()
    
    var body: some View {
        ZStack {
            // Main Chat Interface
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [.lightBlue, .white]),
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Chat area
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 15) {
                                ForEach(messages) { message in
                                    ChatBubble(text: message.text, isUser: message.isUser)
                                        .id(message.id)
                                }
                                if !stats.isEmpty {
                                    StatsView(stats: stats)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 10)
                        }
                        .onChange(of: messages) { _ in
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    
                    // Input area
                    InputBar(
                        userInput: $userInput,
                        isGenerating: $isGenerating,
                        onSend: sendMessage
                    )
                }
            }
            
            // Floating Resource Monitor
            DraggableResourceMonitor()
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TokenGenerationCompleted"))) { _ in
            isGenerating = false  // Re-enable the button when token generation is complete
        }
        .onReceive(SharedTokenUpdater.shared.$decodedTokens) { tokens in
            // update model response
            if let lastIndex = messages.lastIndex(where: { !$0.isUser }) {
                let combinedText = tokens.joined(separator: "")
                messages[lastIndex].text = combinedText
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TokenGenerationStats"))) { notification in
            if let userInfo = notification.userInfo,
               let promptProcRate = userInfo["promptProcRate"] as? Double,
               let tokenGenRate = userInfo["tokenGenRate"] as? Double {
                stats = String(format: "Token generation rate: %.2f tokens/s. Prompt processing rate: %.2f tokens/s", tokenGenRate, promptProcRate)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TokenGenerationError"))) { notification in
            if let userInfo = notification.userInfo, let error = userInfo["error"] as? String {
                    errorMessage = error
                    isGenerating = false
                    showAlert = true
            }
        }
    }
    
    private func sendMessage() {
        guard !userInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        messages.append(Message(text: userInput, isUser: true))
        messages.append(Message(text: "", isUser: false))
        
        SharedTokenUpdater.shared.clearTokens()
        let prompt = userInput
        userInput = ""
        isGenerating = true
        
        DispatchQueue.global(qos: .background).async {
            generator.generate(prompt)
        }
    }
}

struct InputBar: View {
    @Binding var userInput: String
    @Binding var isGenerating: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Enhanced TextField
            TextField("Type your message...", text: $userInput)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.blue)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                )
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 16))
                .textCase(.none)
                .autocorrectionDisabled()
                .foregroundStyle(.primary)
                .submitLabel(.send)
                .onSubmit(onSend)
            
            // Enhanced Send Button
            Button(action: onSend) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(isGenerating ? Color.gray : Color.blue)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
                    .opacity(isGenerating ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isGenerating)
            }
            .disabled(isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1),
            alignment: .top
        )
    }
}

// Fix the CustomTextFieldModifier
struct CustomTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textCase(.none)
            .autocorrectionDisabled()
            .foregroundStyle(.primary)
    }
}

// Add extension to make it easier to use
extension View {
    func customTextField() -> some View {
        modifier(CustomTextFieldModifier())
    }
}

struct ChatBubble: View {
    var text: String
    var isUser: Bool
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            Text(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isUser ? Color.lightBlue : Color.white.opacity(0.8))
                .foregroundColor(isUser ? .white : .black)
                .cornerRadius(20)
                .shadow(radius: 1)
            if !isUser { Spacer() }
        }
    }
}

struct StatsView: View {
    let stats: String
    
    var body: some View {
        Text(stats)
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
    }
}

// Update the Color extension with additional colors
extension Color {
    static let lightBlue = Color(red: 0.4, green: 0.6, blue: 0.9)
    static let inputBackground = Color(red: 0.95, green: 0.95, blue: 0.97)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// Add this new view for the draggable resource monitor
struct DraggableResourceMonitor: View {
    @State private var position = CGPoint(x: 20, y: 20)
    @State private var isDragging = false
    @State private var opacity: Double = 0.9
    @GestureState private var dragOffset = CGSize.zero
    
    var body: some View {
        SystemStatsView()
            .opacity(isDragging ? 0.7 : opacity)
            .frame(width: 220)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.2), radius: 5)
            .position(x: position.x + dragOffset.width, y: position.y + dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                        isDragging = true
                    }
                    .onEnded { value in
                        position.x += value.translation.width
                        position.y += value.translation.height
                        isDragging = false
                    }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    opacity = hovering ? 1.0 : 0.9
                }
            }
    }
}
