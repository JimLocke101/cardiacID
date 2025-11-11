import Foundation

/// Todo model for Supabase integration
struct Todo: Identifiable, Codable {
    let id: Int
    let title: String
    let completed: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let userId: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case completed
        case createdAt = "created_at"
        case updatedAt = "updated_at" 
        case userId = "user_id"
    }
    
    init(id: Int, title: String, completed: Bool? = false, createdAt: Date? = nil, updatedAt: Date? = nil, userId: String? = nil) {
        self.id = id
        self.title = title
        self.completed = completed ?? false
        self.createdAt = createdAt ?? Date()
        self.updatedAt = updatedAt ?? Date()
        self.userId = userId
    }
}

// MARK: - Todo Extensions

extension Todo {
    /// Creates a new todo for insertion (without ID)
    struct TodoInsert: Codable {
        let title: String
        let completed: Bool
        let userId: String?
        
        enum CodingKeys: String, CodingKey {
            case title
            case completed
            case userId = "user_id"
        }
        
        init(title: String, completed: Bool = false, userId: String? = nil) {
            self.title = title
            self.completed = completed
            self.userId = userId
        }
    }
    
    /// Creates a todo update struct (for partial updates)
    struct TodoUpdate: Codable {
        let title: String?
        let completed: Bool?
        let updatedAt: Date?
        
        enum CodingKeys: String, CodingKey {
            case title
            case completed
            case updatedAt = "updated_at"
        }
        
        init(title: String? = nil, completed: Bool? = nil) {
            self.title = title
            self.completed = completed
            self.updatedAt = Date()
        }
    }
}

// MARK: - Todo Service

/// Service for managing todos with Supabase
class TodoService {
    private let supabase = SupabaseConfiguration.client
    
    /// Fetch all todos
    func fetchTodos() async throws -> [Todo] {
        return try await supabase
            .from("todos")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    /// Fetch todos for a specific user
    func fetchTodos(for userId: String) async throws -> [Todo] {
        return try await supabase
            .from("todos")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    /// Create a new todo
    func createTodo(title: String, userId: String? = nil) async throws -> Todo {
        let newTodo = Todo.TodoInsert(title: title, userId: userId)
        
        return try await supabase
            .from("todos")
            .insert(newTodo)
            .select()
            .single()
            .execute()
            .value
    }
    
    /// Update an existing todo
    func updateTodo(id: Int, title: String? = nil, completed: Bool? = nil) async throws -> Todo {
        let update = Todo.TodoUpdate(title: title, completed: completed)
        
        return try await supabase
            .from("todos")
            .update(update)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }
    
    /// Delete a todo
    func deleteTodo(id: Int) async throws {
        try await supabase
            .from("todos")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    /// Toggle todo completion status
    func toggleTodo(id: Int) async throws -> Todo {
        // First fetch the current todo to get its completion status
        let currentTodo: Todo = try await supabase
            .from("todos")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
        
        // Toggle the completion status
        let newCompletedStatus = !(currentTodo.completed ?? false)
        
        return try await updateTodo(id: id, completed: newCompletedStatus)
    }
}