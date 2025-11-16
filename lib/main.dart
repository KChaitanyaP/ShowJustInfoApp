import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert';
import 'package:http/http.dart' as http;

const apiUrl = "https://showjustinfoappbackend.onrender.com/quote";

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

List<String> _quotes = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize time zones
  tzdata.initializeTimeZones();

  // Initialize notifications
  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: initSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Request permission (Android 13+)
  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();

  // Initialize Alarm Manager for periodic notifications
  await AndroidAlarmManager.initialize();

  // Periodic alarm (every 15 minutes)
  await AndroidAlarmManager.periodic(
    const Duration(minutes: 15),
    0,
    showRandomQuoteNotification,
    wakeup: true,
    rescheduleOnReboot: true,
  );

  runApp(const MyApp());
}

Future<String?> fetchQuoteFromAPI() async {
  try {
    final response = await http.get(Uri.parse(apiUrl));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["quote"]; // API returns { quote: "...", author: "..." }
    } else {
      print("Error: ${response.statusCode}");
      return null;
    }
  } catch (e) {
    print("API call failed: $e");
    return null;
  }
}


Future<void> showRandomQuoteNotification() async {
  // if (_quotes.isEmpty) {
  //  final quotesString = await rootBundle.loadString('assets/quotes.txt');
  //  _quotes = quotesString.split('\n').where((q) => q.isNotEmpty).toList();
  // }
  //
  // if (_quotes.isEmpty) return;
  //
  // final random = Random();
  // final quote = _quotes[random.nextInt(_quotes.length)];

  final apiQuote = await fetchQuoteFromAPI();
  if (apiQuote == null) return;
  final quote = apiQuote;

  const androidDetails = AndroidNotificationDetails(
    'random_quote_channel',
    'Random Quotes',
    channelDescription: 'Shows a random motivational quote',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
  );

  const platformDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    0,
    'Motivational Quote 💫',
    quote,
    platformDetails,
  );
}

// Schedule notification at user-selected DateTime
Future<void> scheduleQuoteNotification(DateTime dateTime) async {
  final india = tz.getLocation('Asia/Kolkata');
  final scheduledTime = tz.TZDateTime.from(dateTime, india);

  if (_quotes.isEmpty) {
    final quotesString = await rootBundle.loadString('assets/quotes.txt');
    _quotes = quotesString.split('\n').where((q) => q.isNotEmpty).toList();
  }

  if (_quotes.isEmpty) return;

  final random = Random();
  final quote = _quotes[random.nextInt(_quotes.length)];

  const androidDetails = AndroidNotificationDetails(
    'scheduled_quote_channel',
    'Scheduled Quotes',
    channelDescription: 'Quotes scheduled by the user',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
  );

  const platformDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.zonedSchedule(
    1,
    'Your Scheduled Quote 💫',
    quote,
    scheduledTime,
    platformDetails,
    androidAllowWhileIdle: true,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Random Quotes',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _quote = "Tap the button to get a random quote!";
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    final quotesString = await rootBundle.loadString('assets/quotes.txt');
    setState(() {
      _quotes = quotesString.split('\n').where((q) => q.isNotEmpty).toList();
      // _setRandomQuote();
      _fetchAndSetQuote();
    });
  }

  Future<void> _fetchAndSetQuote() async {
    final quote = await fetchQuoteFromAPI();
    if (quote != null) {
      setState(() {
        _quote = quote;
      });
    }
  }

  void _setRandomQuote() {
    if (_quotes.isNotEmpty) {
      setState(() {
        _quote = _quotes[_random.nextInt(_quotes.length)];
      });
    }
  }

  // Opens calendar and time picker
  Future<void> _pickDateTimeAndSchedule() async {
    final now = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
    );

    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null) return;

    final selectedDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    await scheduleQuoteNotification(selectedDateTime);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Quote scheduled for ${pickedTime.format(context)}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Random Quotes')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _quote,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _fetchAndSetQuote,
                child: const Text('New Quote'),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _pickDateTimeAndSchedule,
                icon: const Icon(Icons.alarm),
                label: const Text('Schedule Quote'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
