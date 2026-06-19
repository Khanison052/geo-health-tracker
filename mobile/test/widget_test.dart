// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('GeoHealthApp loads home screen', (WidgetTester tester) async {
    // Build the app and wait for the first frame.
    await tester.pumpWidget(const GeoHealthApp());
    await tester.pumpAndSettle();

    // Verify the home screen and primary UI elements are visible.
    expect(find.text('สวัสดีครับ'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
