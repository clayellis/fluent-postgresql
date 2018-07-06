extension PostgreSQLDatabase: SQLConstraintIdentifierNormalizer {
    /// See `SQLConstraintIdentifierNormalizer`.
    public static func normalizeSQLConstraintIdentifier(_ identifier: String) -> String {
        return identifier
    }
}

extension PostgreSQLDatabase: SchemaSupporting {
    /// See `SchemaSupporting`.
    public typealias Schema = FluentPostgreSQLSchema
    
    /// See `SchemaSupporting`.
    public typealias SchemaAction = FluentPostgreSQLSchemaStatement
    
    /// See `SchemaSupporting`.
    public typealias SchemaField = PostgreSQLColumnDefinition
    
    /// See `SchemaSupporting`.
    public typealias SchemaFieldType = PostgreSQLDataType
    
    /// See `SchemaSupporting`.
    public typealias SchemaConstraint = PostgreSQLTableConstraint
    
    /// See `SchemaSupporting`.
    public typealias SchemaReferenceAction = PostgreSQLForeignKeyAction
    
    /// See `SchemaSupporting`.
    public static func schemaExecute(_ fluent: FluentPostgreSQLSchema, on conn: PostgreSQLConnection) -> Future<Void> {
        let query: PostgreSQLQuery
        switch fluent.statement {
        case ._createTable:
            var createTable: PostgreSQLCreateTable = .createTable(fluent.table)
            createTable.columns = fluent.columns
            createTable.tableConstraints = fluent.constraints
            query = ._createTable(createTable)
        case ._alterTable:
            var alterTable: PostgreSQLAlterTable = .alterTable(fluent.table)
            alterTable.columns = fluent.columns
            alterTable.constraints = fluent.constraints
            alterTable.dropActions += fluent.deleteColumns.map { .init(.column, $0.identifier) }
            alterTable.dropActions += fluent.deleteConstraints.map {
                guard let id = $0.identifier else {
                    fatalError("Cannot drop constraint without identifier: \($0).")
                }
                return .init(.constraint, id)
            }
            query = ._alterTable(alterTable)
        case ._dropTable:
            let dropTable: PostgreSQLDropTable = .dropTable(fluent.table)
            query = ._dropTable(dropTable)
        }
        return conn.query(query).transform(to: ())
    }
    
    /// See `SchemaSupporting`.
    public static func schemaField(for type: Any.Type, isIdentifier: Bool, _ column: PostgreSQLColumnIdentifier) -> PostgreSQLColumnDefinition {
        var constraints: [PostgreSQLColumnConstraint] = []
        var dataType: PostgreSQLDataType
        
        var type = type
        if let optional = type as? AnyOptionalType.Type {
            type = optional.anyWrappedType
            if isIdentifier {
                constraints.append(.notNull)
            }
        } else {
            constraints.append(.notNull)
        }
        
        let isArray: Bool
        if let array = type as? AnyArray.Type {
            type = array.anyElementType
            isArray = true
        } else {
            isArray = false
        }
        
        if let type = type as? PostgreSQLDataTypeStaticRepresentable.Type {
            dataType = type.postgreSQLDataType
        } else {
            dataType = .jsonb
        }
        
        if isIdentifier {
            let pkDefault: PostgreSQLPrimaryKeyDefault?
            // create a unique name for the primary key since it will be added
            // as a separate index.
            let unique: String
            if let table = column.table {
                unique = table.identifier.string + "." + column.identifier.string
            } else {
                unique = column.identifier.string
            }
            if _globalEnableIdentityColumns {
                switch dataType {
                case .smallint, .integer, .bigint:
                    pkDefault = .generated(.byDefault)
                default:
                    pkDefault = nil
                }
            } else {
                pkDefault = nil
                switch dataType {
                case .smallint: dataType = .smallserial
                case .integer: dataType = .serial
                case .bigint: dataType = .bigserial
                default: break
                }
            }
            constraints.append(.primaryKey(default: pkDefault, identifier: .identifier("pk:\(unique)")))
        }
        
        if isArray {
            dataType = .array(dataType)
        }
        
        return .columnDefinition(column, dataType, constraints)
    }
    
    /// See `SchemaSupporting`.
    public static func enableReferences(on connection: PostgreSQLConnection) -> Future<Void> {
        // enabled by default
        return .done(on: connection)
    }
    
    /// See `SchemaSupporting`.
    public static func disableReferences(on connection: PostgreSQLConnection) -> Future<Void> {
        return Future.map(on: connection) {
            throw PostgreSQLError(identifier: "disableReferences", reason: "PostgreSQL does not support disabling foreign key checks.")
        }
    }
}
