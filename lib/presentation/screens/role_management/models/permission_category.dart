import 'package:flutter/material.dart';

class PermissionCategory {
  final String name;
  final IconData icon;
  final Color color;
  final Map<String, String> permissions;

  const PermissionCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.permissions,
  });
}
