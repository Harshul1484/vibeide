class Project {
  final String id;
  final String name;
  final String remoteUrl;
  final String branch;
  final String localPath;
  final DateTime lastOpened;

  const Project({
    required this.id,
    required this.name,
    required this.remoteUrl,
    required this.branch,
    required this.localPath,
    required this.lastOpened,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'remoteUrl': remoteUrl,
        'branch': branch,
        'localPath': localPath,
        'lastOpened': lastOpened.millisecondsSinceEpoch,
      };

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        remoteUrl: m['remoteUrl'] as String,
        branch: m['branch'] as String,
        localPath: m['localPath'] as String,
        lastOpened: DateTime.fromMillisecondsSinceEpoch(m['lastOpened'] as int),
      );

  Project copyWith({String? branch, DateTime? lastOpened}) => Project(
        id: id,
        name: name,
        remoteUrl: remoteUrl,
        branch: branch ?? this.branch,
        localPath: localPath,
        lastOpened: lastOpened ?? this.lastOpened,
      );
}
