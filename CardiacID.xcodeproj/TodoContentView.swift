import SwiftUI
import Supabase

/// Example ContentView showing Todo integration with Supabase
struct TodoContentView: View {
    @State private var todos: [Todo] = []
    @State private var newTodoTitle = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let todoService = TodoService()
    
    var body: some View {
        NavigationStack {
            VStack {
                // Add new todo section
                HStack {
                    TextField("Enter new todo...", text: $newTodoTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Add") {
                        Task {
                            await createTodo()
                        }
                    }
                    .disabled(newTodoTitle.isEmpty || isLoading)
                }
                .padding(.horizontal)
                
                // Todos list
                if isLoading {
                    Spacer()
                    ProgressView("Loading todos...")
                    Spacer()
                } else if todos.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "checklist")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No todos yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Add your first todo above")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(todos) { todo in
                            TodoRowView(
                                todo: todo,
                                onToggle: { todoId in
                                    Task {
                                        await toggleTodo(id: todoId)
                                    }
                                },
                                onDelete: { todoId in
                                    Task {
                                        await deleteTodo(id: todoId)
                                    }
                                }
                            )
                        }
                        .onDelete(perform: deleteTodos)
                    }
                }
            }
            .navigationTitle("Todos")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await loadTodos()
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadTodos()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    // MARK: - Todo Operations
    
    private func loadTodos() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedTodos = try await todoService.fetchTodos()
            await MainActor.run {
                self.todos = fetchedTodos
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load todos: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func createTodo() async {
        guard !newTodoTitle.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let newTodo = try await todoService.createTodo(title: newTodoTitle)
            await MainActor.run {
                self.todos.insert(newTodo, at: 0)
                self.newTodoTitle = ""
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to create todo: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func toggleTodo(id: Int) async {
        do {
            let updatedTodo = try await todoService.toggleTodo(id: id)
            await MainActor.run {
                if let index = todos.firstIndex(where: { $0.id == id }) {
                    todos[index] = updatedTodo
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to update todo: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteTodo(id: Int) async {
        do {
            try await todoService.deleteTodo(id: id)
            await MainActor.run {
                todos.removeAll { $0.id == id }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete todo: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteTodos(offsets: IndexSet) {
        for index in offsets {
            let todo = todos[index]
            Task {
                await deleteTodo(id: todo.id)
            }
        }
    }
}

// MARK: - Todo Row View

struct TodoRowView: View {
    let todo: Todo
    let onToggle: (Int) -> Void
    let onDelete: (Int) -> Void
    
    var body: some View {
        HStack {
            Button(action: {
                onToggle(todo.id)
            }) {
                Image(systemName: (todo.completed ?? false) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor((todo.completed ?? false) ? .green : .gray)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .font(.body)
                    .strikethrough(todo.completed ?? false)
                    .foregroundColor((todo.completed ?? false) ? .secondary : .primary)
                
                if let createdAt = todo.createdAt {
                    Text(DateFormatter.shortDateTime.string(from: createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                onDelete(todo.id)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Preview

#Preview {
    TodoContentView()
}

// MARK: - Usage in your main ContentView

/*
 To integrate this into your main app, you can either:
 
 1. Replace your existing ContentView with TodoContentView
 2. Add it as a tab in a TabView
 3. Navigate to it from your main interface
 
 Example integration:
 
 struct ContentView: View {
     var body: some View {
         TabView {
             TodoContentView()
                 .tabItem {
                     Image(systemName: "checklist")
                     Text("Todos")
                 }
             
             // Your other views...
         }
     }
 }
 */