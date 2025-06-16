import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  void _showImagePopup(String imageUrl) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Theme.of(context).cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurface,
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const CircularProgressIndicator();
                  },
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Close',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePermission(String docId, String faceId, String status, String requestId) async {
    try {
      // Update the pending_permissions collection
      await FirebaseFirestore.instance.collection('pending_permissions').doc(docId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update the registered_faces collection
      final userSnapshot = await FirebaseFirestore.instance
          .collection('registered_faces')
          .where('faceId', isEqualTo: faceId)
          .where('currentRequestId', isEqualTo: requestId)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        final userDoc = userSnapshot.docs.first;
        await userDoc.reference.update({
          'status': status,
          'currentRequestId': null, // Clear the requestId after processing
          'hasStartedVehicle': status == 'accepted' ? true : false,
          'lastStartVehicle': status == 'accepted' ? FieldValue.serverTimestamp() : userDoc['lastStartVehicle'],
        });

        // Log the action in face_notifications
        await FirebaseFirestore.instance.collection('face_notifications').add({
          'faceId': faceId,
          'message': 'User $faceId has been ${status == 'accepted' ? 'approved' : 'rejected'}',
          'timestamp': FieldValue.serverTimestamp(),
        });

        if (status == 'accepted') {
          print('User $faceId accepted with requestId $requestId and vehicle started at ${DateTime.now()}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User approved successfully')),
          );
        } else {
          print('User $faceId rejected with requestId $requestId at ${DateTime.now()}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User rejected successfully')),
          );
        }
      } else {
        print('User not found or requestId mismatch for faceId: $faceId at ${DateTime.now()}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not found or request ID mismatch')),
        );
      }

      // Force a UI refresh by rebuilding the widget
      setState(() {});
    } catch (e) {
      print('Error handling permission for $faceId: $e at ${DateTime.now()}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error handling permission: $e')),
      );
    }
  }

  Widget _buildUserTile(Map<String, dynamic> user, {String? timestampField = 'timestamp'}) {
    final timestamp = user[timestampField] as DateTime?;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: GestureDetector(
          onTap: user['photoUrl'] != null
              ? () => _showImagePopup(user['photoUrl'])
              : null,
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.surface,
            child: user['photoUrl'] != null
                ? ClipOval(
              child: Image.network(
                user['photoUrl'],
                fit: BoxFit.cover,
                width: 48,
                height: 48,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const CircularProgressIndicator();
                },
              ),
            )
                : Icon(
              Icons.person,
              color: Theme.of(context).colorScheme.onSurface,
              size: 24,
            ),
          ),
        ),
        title: timestamp != null
            ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${timestampField == 'lastStartVehicle' ? 'Used on' : 'Registered on'}: ${DateFormat('yyyy-MM-dd').format(timestamp)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Time: ${DateFormat('HH:mm:ss').format(timestamp)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        )
            : Text(
          'Date Unknown',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            user['faceId'],
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> notification) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: GestureDetector(
          onTap: notification['photoUrl'] != null
              ? () => _showImagePopup(notification['photoUrl'])
              : null,
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.surface,
            child: notification['photoUrl'] != null
                ? ClipOval(
              child: Image.network(
                notification['photoUrl'],
                fit: BoxFit.cover,
                width: 48,
                height: 48,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const CircularProgressIndicator();
                },
              ),
            )
                : Icon(
              Icons.person,
              color: Theme.of(context).colorScheme.onSurface,
              size: 24,
            ),
          ),
        ),
        title: Text(
          notification['message'] ?? 'New Face Registered',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: notification['timestamp'] != null
            ? Text(
          'Registered on: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(notification['timestamp'])}',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
          ),
        )
            : Text(
          'Time Unknown',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildPendingPermissionTile(Map<String, dynamic> permission) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      color: Theme.of(context).cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            GestureDetector(
              onTap: permission['photoUrl'] != null
                  ? () => _showImagePopup(permission['photoUrl'])
                  : null,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: permission['photoUrl'] != null
                    ? ClipOval(
                  child: Image.network(
                    permission['photoUrl'],
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.person,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 24,
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const CircularProgressIndicator();
                    },
                  ),
                )
                    : Icon(
                  Icons.person,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    permission['faceId'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    permission['timestamp'] != null
                        ? 'Requested on: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(permission['timestamp'])}'
                        : 'Time Unknown',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.check, color: Colors.green),
                  onPressed: () async {
                    await _handlePermission(permission['docId'], permission['faceId'], 'accepted', permission['requestId']);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.red),
                  onPressed: () async {
                    await _handlePermission(permission['docId'], permission['faceId'], 'rejected', permission['requestId']);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Registered Users'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: ListView(
          children: [
            // Pending Permissions Section
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('pending_permissions')
                  .where('status', isEqualTo: 'pending')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print('Error in Pending Permissions: ${snapshot.error} at ${DateTime.now()}');
                  return Center(
                    child: Text(
                      'Error loading pending permissions: ${snapshot.error}',
                      style: const TextStyle(fontSize: 18, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final permissions = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'docId': doc.id,
                    'faceId': data['faceId'] as String,
                    'photoUrl': data.containsKey('photoUrl') ? data['photoUrl'] : null,
                    'timestamp': data.containsKey('timestamp') && data['timestamp'] != null
                        ? (data['timestamp'] as Timestamp).toDate()
                        : null,
                    'status': data['status'] as String,
                    'requestId': data.containsKey('requestId') ? data['requestId'] as String : null,
                  };
                }).where((permission) => permission['timestamp'] != null).toList();

                if (permissions.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Pending Permissions',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    ...permissions.map((permission) => _buildPendingPermissionTile(permission)).toList(),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Face Registration Notifications Section
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('face_notifications')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print('Error in Face Registration Notifications: ${snapshot.error} at ${DateTime.now()}');
                  return Center(
                    child: Text(
                      'Error loading notifications: ${snapshot.error}',
                      style: const TextStyle(fontSize: 18, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final notifications = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'faceId': data['faceId'] as String,
                    'photoUrl': data.containsKey('photoUrl') ? data['photoUrl'] : null,
                    'timestamp': data.containsKey('timestamp') && data['timestamp'] != null
                        ? (data['timestamp'] as Timestamp).toDate()
                        : null,
                    'message': data.containsKey('message') ? data['message'] as String : null,
                  };
                }).where((notification) => notification['timestamp'] != null).toList();

                if (notifications.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Face Registration Notifications',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    ...notifications.map((notification) => _buildNotificationTile(notification)).toList(),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Current User (Now Using) Section
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('registered_faces')
                  .where('hasStartedVehicle', isEqualTo: true)
                  .where('status', isEqualTo: 'accepted')
                  .orderBy('lastStartVehicle', descending: true)
                  .limit(1)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print('Error in Now Using: ${snapshot.error} at ${DateTime.now()}');
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(fontSize: 18, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final users = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'faceId': data['faceId'] as String,
                    'photoUrl': data.containsKey('photoUrl') ? data['photoUrl'] : null,
                    'timestamp': data.containsKey('timestamp') && data['timestamp'] != null
                        ? (data['timestamp'] as Timestamp).toDate()
                        : null,
                    'hasStartedVehicle': data.containsKey('hasStartedVehicle') ? data['hasStartedVehicle'] as bool : false,
                    'lastStartVehicle': data.containsKey('lastStartVehicle') && data['lastStartVehicle'] != null
                        ? (data['lastStartVehicle'] as Timestamp).toDate()
                        : null,
                    'status': data.containsKey('status') ? data['status'] as String : 'pending',
                  };
                }).where((user) => user['lastStartVehicle'] != null).toList();

                if (users.isEmpty) {
                  return const SizedBox.shrink();
                }

                final user = users[0];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Now Using',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    _buildUserTile(user, timestampField: 'lastStartVehicle'),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Already Used Section
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('registered_faces')
                  .where('lastStartVehicle', isNotEqualTo: null)
                  .where('hasStartedVehicle', isEqualTo: false) // Exclude current users
                  .orderBy('lastStartVehicle', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print('Error in Already Used: ${snapshot.error} at ${DateTime.now()}');
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(fontSize: 18, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final users = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'faceId': data['faceId'] as String,
                    'photoUrl': data.containsKey('photoUrl') ? data['photoUrl'] : null,
                    'timestamp': data.containsKey('timestamp') && data['timestamp'] != null
                        ? (data['timestamp'] as Timestamp).toDate()
                        : null,
                    'hasStartedVehicle': data.containsKey('hasStartedVehicle') ? data['hasStartedVehicle'] as bool : false,
                    'lastStartVehicle': data.containsKey('lastStartVehicle') && data['lastStartVehicle'] != null
                        ? (data['lastStartVehicle'] as Timestamp).toDate()
                        : null,
                    'status': data.containsKey('status') ? data['status'] as String : 'pending',
                  };
                }).where((user) => user['lastStartVehicle'] != null).toList();

                if (users.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Already Used',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    ...users.map((user) => _buildUserTile(user, timestampField: 'lastStartVehicle')).toList(),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Approved Users Section
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('registered_faces')
                  .where('status', isEqualTo: 'accepted')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print('Error in Approved Users: ${snapshot.error} at ${DateTime.now()}');
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(fontSize: 18, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final users = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'faceId': data['faceId'] as String,
                    'photoUrl': data.containsKey('photoUrl') ? data['photoUrl'] : null,
                    'timestamp': data.containsKey('timestamp') && data['timestamp'] != null
                        ? (data['timestamp'] as Timestamp).toDate()
                        : null,
                    'hasStartedVehicle': data.containsKey('hasStartedVehicle') ? data['hasStartedVehicle'] as bool : false,
                    'lastStartVehicle': data.containsKey('lastStartVehicle') && data['lastStartVehicle'] != null
                        ? (data['lastStartVehicle'] as Timestamp).toDate()
                        : null,
                    'status': data.containsKey('status') ? data['status'] as String : 'pending',
                  };
                }).where((user) => user['timestamp'] != null).toList();

                if (users.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Approved',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    ...users.map((user) => _buildUserTile(user)).toList(),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Rejected Users Section
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('registered_faces')
                  .where('status', isEqualTo: 'rejected')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  print('Error in Rejected Users: ${snapshot.error} at ${DateTime.now()}');
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(fontSize: 18, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                final users = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return {
                    'faceId': data['faceId'] as String,
                    'photoUrl': data.containsKey('photoUrl') ? data['photoUrl'] : null,
                    'timestamp': data.containsKey('timestamp') && data['timestamp'] != null
                        ? (data['timestamp'] as Timestamp).toDate()
                        : null,
                    'hasStartedVehicle': data.containsKey('hasStartedVehicle') ? data['hasStartedVehicle'] as bool : false,
                    'lastStartVehicle': data.containsKey('lastStartVehicle') && data['lastStartVehicle'] != null
                        ? (data['lastStartVehicle'] as Timestamp).toDate()
                        : null,
                    'status': data.containsKey('status') ? data['status'] as String : 'pending',
                  };
                }).where((user) => user['timestamp'] != null).toList();

                if (users.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Rejected',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    ...users.map((user) => _buildUserTile(user)).toList(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}