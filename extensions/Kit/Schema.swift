import Foundation

/// JSON Schema pieces for tool inputs, as the model reads them. Every object refuses keys it doesn't list.
public enum Schema {
    public static var none: [String: Any] { object([:]) }

    public static func object(_ properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    public static func string(_ description: String, minLength: Int = 1, maxLength: Int = 200, oneOf values: [String]? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string", "description": description, "minLength": minLength, "maxLength": maxLength]
        if let values { schema["enum"] = values }
        return schema
    }

    public static func integer(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> [String: Any] {
        bounded(["type": "integer", "description": description], minimum, maximum)
    }

    public static func number(_ description: String, minimum: Double? = nil, maximum: Double? = nil) -> [String: Any] {
        bounded(["type": "number", "description": description], minimum, maximum)
    }

    public static func boolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    public static func array(of item: [String: Any], _ description: String, minItems: Int = 1, maxItems: Int = 20) -> [String: Any] {
        ["type": "array", "items": item, "description": description, "minItems": minItems, "maxItems": maxItems]
    }

    /// A file or folder the person names; Sidefolk checks it and opens just that one for the call
    /// (the manifest's `tools.<name>.paths`).
    public static func path(_ description: String) -> [String: Any] {
        string(description, maxLength: 1024)
    }

    private static func bounded(_ base: [String: Any], _ minimum: Any?, _ maximum: Any?) -> [String: Any] {
        var schema = base
        if let minimum { schema["minimum"] = minimum }
        if let maximum { schema["maximum"] = maximum }
        return schema
    }
}
