import 'package:flutter/material.dart';

import 'features/home/household_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HouseHolderApp());
}

class HouseHolderApp extends StatelessWidget {
  const HouseHolderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HouseHolder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HouseholdHomePage(),
    );
  }
}
