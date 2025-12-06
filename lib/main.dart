import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

const apiUrl = "https://showjustinfoappbackend.onrender.com";

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

List<String> _quotes = [];

//
// ------------------------ LOCATION PERMISSION ------------------------
//
Future<bool> handleLocationPermission() async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    await Geolocator.openLocationSettings();
    return false;
  }

  permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return false;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    return false;
  }

  return true;
}

//
// ------------------------ MAIN ENTRY ------------------------
//
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tzdata.initializeTimeZones();

  const AndroidInitializationSettings initSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: initSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();

  await AndroidAlarmManager.initialize();

  await AndroidAlarmManager.periodic(
    const Duration(minutes: 15),
    0,
    showRandomQuoteNotification,
    wakeup: true,
    rescheduleOnReboot: true,
  );

  runApp(const MyApp());
}

//
// ------------------------ QUOTE API CALL ------------------------
//
Future<String?> fetchQuoteFromAPI() async {
  try {
    final response = await http
        .get(Uri.parse("$apiUrl/quote"))
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["quote"];
    } else {
      return "Server error: ${response.statusCode}";
    }
  } on TimeoutException {
    return "Server is waking up… please try again!";
  } catch (e) {
    return "Network error: $e";
  }
}

//
// ------------------------ QUOTE NOTIFICATION ------------------------
//
Future<void> showRandomQuoteNotification() async {
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

//
// ------------------------ SCHEDULE QUOTE ------------------------
//

Future<void> scheduleQuoteNotification(DateTime dateTime) async {
  final india = tz.getLocation('Asia/Kolkata');
  final scheduledTime = tz.TZDateTime.from(dateTime, india);

  if (_quotes.isEmpty) {
    final quotesString = await rootBundle.loadString('assets/quotes.txt');
    _quotes = quotesString.split('\n').where((q) => q.isNotEmpty).toList();
  }

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

//
// ------------------------ APP ------------------------
//

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
    Future<void> _pickDateTimeAndSchedule() async {
    // Pick Date
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (pickedDate == null) return;

    // Pick Time
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (pickedTime == null) return;

    final DateTime scheduledDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // Schedule notification
    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Scheduled Notification',
      'This is your scheduled alert.',
      tz.TZDateTime.from(scheduledDateTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'scheduled_channel',
          'Scheduled Notifications',
          channelDescription: 'Notifications for scheduled alarms',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: null,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Notification scheduled at $scheduledDateTime')),
    );
  }

  String _quote = "Tap the button to get a random quote!";
  bool _isLoading = false;
  bool _isTithiLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    final quotesString = await rootBundle.loadString('assets/quotes.txt');
    _quotes = quotesString.split('\n').where((q) => q.isNotEmpty).toList();
    _fetchAndSetQuote();
  }

  //
  // ------------------------ FETCH QUOTE ------------------------
  //
  Future<void> _fetchAndSetQuote() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final quote = await fetchQuoteFromAPI();

    setState(() {
      _isLoading = false;
    });

    if (quote != null) {
      if (quote.startsWith("Server") || quote.startsWith("Network")) {
        setState(() {
          _errorMessage = quote;
        });
      } else {
        setState(() {
          _quote = quote;
        });
      }
    }
  }

  //
  // ------------------------ TITHI FETCH ------------------------
  //
  Future<void> fetchTithi() async {
    setState(() => _isTithiLoading = true);

    try {
      bool hasPermission = await handleLocationPermission();
      if (!hasPermission) {
        showError("Location permission is required to fetch your Tithi.");
        setState(() => _isTithiLoading = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final lat = position.latitude;
      final lon = position.longitude;

      final url = Uri.parse("$apiUrl/tithi?lat=$lat&lon=$lon");

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Today's Tithi"),
            content: Text(
                "Tithi: ${data['tithi']}\nStart: ${data['start']}\nEnd: ${data['end']}"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      } else {
        showError("Failed to fetch Tithi");
      }
    } catch (e) {
      showError("Error: $e");
    }

    setState(() => _isTithiLoading = false);
  }

  void showError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  //
  // ------------------------ UI ------------------------
  //
  Widget _buildQuoteDisplay() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Text(
        _errorMessage!,
        style: const TextStyle(color: Colors.red, fontSize: 18),
        textAlign: TextAlign.center,
      );
    }

    return Text(
      _quote,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 24,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.bold,
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
              _buildQuoteDisplay(),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),

              const SizedBox(height: 40),

              // ------------------------ TITHI BUTTON WITH LOADER ------------------------
              _isTithiLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: fetchTithi,
                      child: const Text("Today's Tithi"),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
