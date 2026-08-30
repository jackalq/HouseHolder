import 'package:flutter/material.dart';

void main() {
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
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HouseHolder')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '家庭管家',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text('先從課表、購物與待辦開始。'),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍課表'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.mic_none),
                    label: const Text('語音'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text('購物清單'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.checklist_outlined),
                    label: const Text('待辦'),
                  ),
                ],
              ),
              const Spacer(),
              TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '例如：明天有什麼課？',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.send),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
