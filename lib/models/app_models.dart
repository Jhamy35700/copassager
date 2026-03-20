import 'package:latlong2/latlong.dart';

class AppUser {
  String name;
  String password;
  String transport;
  String firstName;
  String lastName;
  String address;

  AppUser({
    this.name = "",
    this.password = "",
    this.transport = "avion",
    this.firstName = "",
    this.lastName = "",
    this.address = "",
  });
}

class Room {
  final String id;
  final String author;
  final String title;
  final String? desc;
  final String type;
  final String transport;
  final String? tripNumber;
  final double? lat;
  final double? lng;
  final bool isOnline;

  Room({
    required this.id,
    required this.author,
    required this.title,
    this.desc,
    required this.type,
    required this.transport,
    this.tripNumber,
    this.lat,
    this.lng,
    this.isOnline = true,
  });
}

class ChatMessage {
  final String text;
  final String time;
  final bool isMe;

  ChatMessage({
    required this.text,
    required this.time,
    required this.isMe,
  });
}