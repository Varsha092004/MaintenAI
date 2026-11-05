
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const Color bg = Color(0xFF0B1120);
const Color panel = Color(0xFF111C30);
const Color card = Color(0xFF18253B);
const Color accent = Color(0xFF2DD4BF);
const Color muted = Color(0xFF94A3B8);

void main() {
  runApp(const MaintenAI());
}

class MaintenAI extends StatelessWidget {
  const MaintenAI({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MaintenAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ChatDashboard(),
    );
  }
}

class MachineSettings {
  final machineId = TextEditingController(text: 'MACHINE-001');
  final machineType = TextEditingController(text: 'M');
  final airTemp = TextEditingController(text: '298.1');
  final processTemp = TextEditingController(text: '308.6');
  final rpm = TextEditingController(text: '1500');
  final torque = TextEditingController(text: '40');
  final toolWear = TextEditingController(text: '120');

  Map<String, dynamic> toJson() {
    return {
      'machine_id': machineId.text.trim(),
      'machine_type': machineType.text.trim().toUpperCase(),
      'air_temperature': double.parse(airTemp.text),
      'process_temperature': double.parse(processTemp.text),
      'rotational_speed': double.parse(rpm.text),
      'torque': double.parse(torque.text),
      'tool_wear': double.parse(toolWear.text),
    };
  }

  void dispose() {
    machineId.dispose();
    machineType.dispose();
    airTemp.dispose();
    processTemp.dispose();
    rpm.dispose();
    torque.dispose();
    toolWear.dispose();
  }
}

class ChatMessage {
  final bool isUser;
  final String text;
  final List<dynamic> sources;
  final Map<String, dynamic>? analysis;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.sources = const [],
    this.analysis,
  });
}

class ChatSession {
  final String title;
  final List<ChatMessage> messages;

  ChatSession({
    required this.title,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];
}

class ChatDashboard extends StatefulWidget {
  const ChatDashboard({super.key});

  @override
  State<ChatDashboard> createState() => _ChatDashboardState();
}

class _ChatDashboardState extends State<ChatDashboard> {
  static const String apiBase = 'http://127.0.0.1:8000';

  final TextEditingController messageController =
      TextEditingController();
  final MachineSettings machine = MachineSettings();
  final ScrollController scrollController = ScrollController();

  final List<ChatSession> sessions = [
    ChatSession(title: 'New conversation'),
  ];

  int activeSession = 0;
  bool loading = false;
  bool backendOnline = false;

  List<ChatMessage> get messages =>
      sessions[activeSession].messages;

  @override
  void initState() {
    super.initState();
    checkBackend();
  }

  @override
  void dispose() {
    messageController.dispose();
    machine.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> checkBackend() async {
    try {
      final response = await http
          .get(Uri.parse('$apiBase/health'))
          .timeout(const Duration(seconds: 5));

      if (mounted) {
        setState(() {
          backendOnline = response.statusCode == 200;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => backendOnline = false);
      }
    }
  }

  void addMessage(ChatMessage message) {
    setState(() {
      messages.add(message);
      if (messages.length == 1 && message.isUser) {
        final title = message.text.length > 28
            ? '${message.text.substring(0, 28)}...'
            : message.text;
        sessions[activeSession] =
            ChatSession(title: title, messages: messages);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void newChat() {
    setState(() {
      sessions.insert(0, ChatSession(title: 'New conversation'));
      activeSession = 0;
    });
    messageController.clear();
  }

  Future<void> sendMessage([String? suggested]) async {
    final question = (suggested ?? messageController.text).trim();

    if (question.isEmpty || loading) return;

    messageController.clear();
    addMessage(ChatMessage(isUser: true, text: question));

    setState(() => loading = true);

    try {
      final response = await http
          .post(
            Uri.parse('$apiBase/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'question': question}),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        addMessage(ChatMessage(
          isUser: false,
          text: data['answer']?.toString() ??
              'The assistant returned an empty response.',
          sources: data['sources'] as List? ?? [],
        ));
      } else {
        addMessage(ChatMessage(
          isUser: false,
          text: 'The backend returned an error '
              '(${response.statusCode}).\n${response.body}',
        ));
      }
    } catch (e) {
      addMessage(ChatMessage(
        isUser: false,
        text: 'Unable to connect to the backend.\n'
            'Check that FastAPI is running at $apiBase.\n\n$e',
      ));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> analyzeMachine() async {
    if (loading) return;

    try {
      final input = machine.toJson();

      if (!['L', 'M', 'H'].contains(input['machine_type'])) {
        throw const FormatException(
          'Machine type must be L, M or H.',
        );
      }

      addMessage(ChatMessage(
        isUser: true,
        text: 'Analyse machine ${input['machine_id']} using its '
            'current sensor readings.',
      ));

      setState(() => loading = true);

      final response = await http
          .post(
            Uri.parse('$apiBase/analyze'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(input),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        addMessage(ChatMessage(
          isUser: false,
          text: data['llm_rag_analysis']?.toString() ??
              'No AI analysis was returned.',
          sources: data['sources'] as List? ?? [],
          analysis: {
            'prediction': data['ml_prediction'],
            'probability': data['failure_probability'],
            'machine_id': data['machine_id'],
          },
        ));
      } else {
        addMessage(ChatMessage(
          isUser: false,
          text: 'Machine analysis failed '
              '(${response.statusCode}).\n${response.body}',
        ));
      }
    } catch (e) {
      addMessage(ChatMessage(
        isUser: false,
        text: 'Please check your sensor values and try again.\n$e',
      ));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showMachineSettings() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: panel,
          title: const Row(
            children: [
              Icon(Icons.settings_input_component, color: accent),
              SizedBox(width: 10),
              Text('Machine Configuration'),
            ],
          ),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  sensorField('Machine ID', machine.machineId, ''),
                  sensorField('Machine Type (L / M / H)',
                      machine.machineType, ''),
                  sensorField('Air Temperature', machine.airTemp, 'K'),
                  sensorField(
                      'Process Temperature', machine.processTemp, 'K'),
                  sensorField('Rotational Speed', machine.rpm, 'RPM'),
                  sensorField('Torque', machine.torque, 'Nm'),
                  sensorField('Tool Wear', machine.toolWear, 'min'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                analyzeMachine();
              },
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Analyse Machine'),
            ),
          ],
        );
      },
    );
  }

  Widget sensorField(
    String label,
    TextEditingController controller,
    String unit,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit.isEmpty ? null : unit,
          filled: true,
          fillColor: card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget suggestion(String text, IconData icon) {
    return InkWell(
      onTap: loading ? null : () => sendMessage(text),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 19),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.arrow_forward_ios,
                size: 12, color: muted),
          ],
        ),
      ),
    );
  }

  Widget welcomeScreen() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.precision_manufacturing,
                  size: 42,
                  color: accent,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to MaintenAI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your intelligent predictive maintenance assistant. '
                'Ask questions or analyse your machine using ML, '
                'RAG and Generative AI.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.6),
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'TRY ASKING',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  suggestion(
                    'What is predictive maintenance?',
                    Icons.auto_graph,
                  ),
                  suggestion(
                    'What are the possible causes of tool wear failure?',
                    Icons.build_circle_outlined,
                  ),
                  suggestion(
                    'Explain the five machine failure modes.',
                    Icons.precision_manufacturing,
                  ),
                  suggestion(
                    'What safety precautions should technicians follow?',
                    Icons.health_and_safety_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: showMachineSettings,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Analyse my machine'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: const BorderSide(color: accent),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget analysisSummary(Map<String, dynamic> analysis) {
    final prediction = analysis['prediction']?.toString() ?? 'Unknown';
    final probability =
        analysis['probability']?.toString() ?? 'N/A';
    final failed = prediction.toLowerCase().contains('failure predicted');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: failed ? Colors.redAccent : accent.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MACHINE ANALYSIS RESULT',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                failed ? Icons.warning_amber_rounded : Icons.check_circle,
                color: failed ? Colors.orangeAccent : accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  prediction,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Failure probability: $probability%',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 8),
          Text(
            'Machine ID: ${analysis['machine_id'] ?? 'N/A'}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget sourceSection(List<dynamic> sources) {
    if (sources.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.menu_book_outlined, color: accent, size: 17),
              SizedBox(width: 8),
              Text(
                'RETRIEVED DOCUMENT SOURCES',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ...sources.toSet().map((source) {
            final name = source['source']?.toString() ?? 'Document';
            final page = source['page']?.toString() ?? 'N/A';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.picture_as_pdf,
                    color: Colors.redAccent,
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  Text(
                    'Page $page',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget messageBubble(ChatMessage message) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 650),
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF164E63),
            borderRadius: BorderRadius.circular(17).copyWith(
              bottomRight: const Radius.circular(4),
            ),
          ),
          child: Text(message.text),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: panel,
          border: Border.all(color: Colors.white10),
          borderRadius: BorderRadius.circular(17).copyWith(
            bottomLeft: const Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: accent, size: 19),
                const SizedBox(width: 9),
                const Text(
                  'MaintenAI Assistant',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (message.analysis != null) ...[
              const SizedBox(height: 15),
              analysisSummary(message.analysis!),
            ],
            SelectableText(
              message.text,
              style: const TextStyle(height: 1.65, fontSize: 13.5),
            ),
            sourceSection(message.sources),
          ],
        ),
      ),
    );
  }

  Widget chatInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: const BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Ask MaintenAI anything...',
                        hintStyle: const TextStyle(color: muted),
                        filled: true,
                        fillColor: panel,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 17,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Colors.white12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 54,
                    width: 54,
                    child: FilledButton(
                      onPressed: loading ? null : () => sendMessage(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: bg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'AI-generated guidance may be incomplete. '
                'Always follow official machine safety procedures.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget sidebar() {
    return Container(
      width: 245,
      color: panel,
      padding: const EdgeInsets.fromLTRB(15, 22, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.precision_manufacturing,
                  color: accent, size: 29),
              SizedBox(width: 10),
              Text(
                'MaintenAI',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 21,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: newChat,
              icon: const Icon(Icons.add, size: 19),
              label: const Text('New Chat'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: bg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
          const SizedBox(height: 27),
          const Text(
            'WORKSPACE',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          sidebarItem(
            Icons.dashboard_outlined,
            'Dashboard',
            () => newChat(),
          ),
          sidebarItem(
            Icons.precision_manufacturing_outlined,
            'Machine Monitoring',
            showMachineSettings,
          ),
          const SizedBox(height: 25),
          const Text(
            'RECENT CHATS',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                return InkWell(
                  onTap: () {
                    setState(() => activeSession = index);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: activeSession == index
                          ? Colors.white10
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 16, color: muted),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            sessions[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white12),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 10,
                color: backendOnline ? accent : Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  backendOnline ? 'Backend connected' : 'Backend offline',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
              IconButton(
                tooltip: 'Check connection',
                onPressed: checkBackend,
                icon: const Icon(Icons.refresh, size: 17, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'ML  •  RAG  •  OpenAI LLM',
            style: TextStyle(color: muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget sidebarItem(IconData icon, String title, VoidCallback action) {
    return InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 13,
        ),
        child: Row(
          children: [
            Icon(icon, color: muted, size: 19),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget mainContent() {
    return Column(
      children: [
        Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 23),
          decoration: const BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Maintenance Assistant',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Intelligent machine health and fault analysis',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: showMachineSettings,
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('Machine Settings'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? welcomeScreen()
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      messageBubble(messages[index]),
                ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'MaintenAI is analysing...',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        chatInput(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Scaffold(
            drawer: Drawer(
              backgroundColor: panel,
              child: SafeArea(child: sidebar()),
            ),
            appBar: AppBar(
              backgroundColor: panel,
              title: const Text('MaintenAI'),
              actions: [
                IconButton(
                  onPressed: showMachineSettings,
                  icon: const Icon(Icons.tune, color: accent),
                ),
              ],
            ),
            body: mainContent(),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              sidebar(),
              Expanded(child: mainContent()),
            ],
          ),
        );
      },
    );
  }
}
