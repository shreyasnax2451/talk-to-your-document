import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/chat_screen.dart';
import 'screens/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set system navigation overlay styling for seamless dark mode
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const DocChatApp());
}

class DocChatApp extends StatelessWidget {
  const DocChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'DocChat',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentTabIndex = 0; // 0 = Chat (Home), 1 = Library

  void _navigateToChat() {
    setState(() {
      _currentTabIndex = 0;
    });
  }

  void _navigateToLibrary() {
    setState(() {
      _currentTabIndex = 1;
    });
  }

  void _onNewChat() {
    context.read<AppState>().createNewChat();
    _navigateToChat();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentTabIndex != 0) {
          // If on Library screen, back button steps back to Chat (home)
          _navigateToChat();
        }
      },
      child: IndexedStack(
        index: _currentTabIndex,
        children: [
          ChatScreen(
            onOpenLibrary: _navigateToLibrary,
          ),
          LibraryScreen(
            onNavigateToChat: _navigateToChat,
            onNewChat: _onNewChat,
          ),
        ],
      ),
    );
  }
}
