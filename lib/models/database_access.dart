class DatabaseAccess {
  final String dbName;
  final String access;

  DatabaseAccess({required this.dbName, required this.access});

  factory DatabaseAccess.fromJson(Map<String, dynamic> json) {
    return DatabaseAccess(
      dbName: json["db_name"] ?? "",
      access: json["access"] ?? "read",
    );
  }
}
