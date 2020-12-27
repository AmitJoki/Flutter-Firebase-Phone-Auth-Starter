import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:loading_overlay/loading_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      // Initialize FlutterFire:
      future: _initialization,
      builder: (context, snapshot) {
        // Check for errors
        if (snapshot.hasError) {
          return MaterialApp(
            home: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Once complete, show your application
        if (snapshot.connectionState == ConnectionState.done) {
          return MaterialApp(
            title: 'Phone Authentication',
            theme: ThemeData(
              primarySwatch: Colors.blue,
              visualDensity: VisualDensity.adaptivePlatformDensity,
            ),
            home: Login(title: 'Login'),
          );
        }

        // Otherwise, show something whilst waiting for initialization to complete
        return MaterialApp(
          home: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Home Page"),
      ),
      body: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Logged in!'),
          ElevatedButton(
            onPressed: () {
              FirebaseAuth.instance.signOut();
              SharedPreferences.getInstance().then((prefs) {
                prefs.clear();
              });
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Login()),
              );
            },
            child: Text('Log out'),
          ),
        ]),
      ),
    );
  }
}

class Login extends StatefulWidget {
  Login({Key key, this.title = 'Login'}) : super(key: key);

  final String title;

  @override
  _LoginState createState() => _LoginState();
}

const STEPS = 2;
const LOGGED_IN = 'LOGGED_IN';

class _LoginState extends State<Login> {
  SharedPreferences prefs;
  PhoneNumber number = PhoneNumber();
  TextEditingController _number = TextEditingController();
  TextEditingController _smsCode = TextEditingController();
  String error1 = "";
  String error2 = "";
  String verificationId = "";
  int resendToken = 0;
  int step = 0;
  bool loading = true;
  bool overlay = false;

  redirectToHomePage() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomePage()),
    );
  }

  initState() {
    super.initState();
    initializeApp();
  }

  initializeApp() async {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(LOGGED_IN) == true) redirectToHomePage();
    FirebaseAuth.instance.authStateChanges().listen((User user) {
      if (user == null) {
        // not logged in
        loading = false;
        if (mounted) setState(() {});
      } else {
        prefs.setBool(LOGGED_IN, true);
        redirectToHomePage();
      }
    });
  }

  bool isNumeric(String s) {
    if (s == null) {
      return false;
    }
    return double.tryParse(s) != null;
  }

  isPhoneNumberValid() {
    var numberString = _number.value.text.replaceAll(' ', '');
    // TODO: For now, Indian numbers are alone validated.
    return numberString.isNotEmpty &&
        isNumeric(numberString) &&
        numberString.length == 10;
  }

  canShowNext() {
    if (step == 0) {
      return isPhoneNumberValid();
    }
    return step < STEPS;
  }

  setState(VoidCallback cb) {
    if (mounted)
      super.setState(() {
        cb();
      });
  }

  tryLogin() async {
    setState(() {
      overlay = true;
    });
    await FirebaseAuth.instance.verifyPhoneNumber(
      timeout: Duration(minutes: 1),
      phoneNumber: number.phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        setState(() {
          overlay = false;
        });
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        error1 = "Invalid number/SMS Quota Exceeded. Try again.";
        overlay = false;
        setState(() {});
      },
      codeSent: (String _verificationId, int _resendToken) {
        this.setState(() {
          step = 1;
          overlay = false;
          verificationId = _verificationId;
          _resendToken = resendToken;
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        // Auto-resolution timed out...
        setState(() {
          overlay = false;
        });
      },
    );
  }

  login() async {
    setState(() {
      overlay = true;
    });
    try {
      await FirebaseAuth.instance
          .signInWithCredential(PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: _smsCode.value.text,
      ));
    } catch (e) {
      setState(() {
        overlay = false;
        error2 = "Verification failed. Try again later.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return Scaffold(
          body: Center(
        child: CircularProgressIndicator(),
      ));
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the Login object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: LoadingOverlay(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Stepper(
                  currentStep: step,
                  onStepContinue: () {
                    if (step == 0) {
                      tryLogin();
                      return;
                    }
                    login();
                  },
                  onStepCancel: () {
                    setState(() {
                      step -= 1;
                    });
                  },
                  onStepTapped: (step) {
                    this.setState(() {
                      this.step = step;
                    });
                  },
                  controlsBuilder: (context, {onStepCancel, onStepContinue}) {
                    return ButtonBar(
                      children: [
                        step > 0
                            ? RaisedButton(
                                child: Text('Back'),
                                onPressed: onStepCancel,
                              )
                            : null,
                        canShowNext()
                            ? RaisedButton(
                                color: Colors.blue,
                                child: Text('Next'),
                                onPressed: onStepContinue,
                              )
                            : null,
                      ],
                    );
                  },
                  steps: [
                    Step(
                        title: Text('Phone Number'),
                        subtitle: error1.isNotEmpty ? Text(error1) : null,
                        content: InternationalPhoneNumberInput(
                          initialValue: PhoneNumber(
                              isoCode: "IN", dialCode: "+91", phoneNumber: ""),
                          textFieldController: _number,
                          selectorConfig: SelectorConfig(
                              selectorType:
                                  PhoneInputSelectorType.BOTTOM_SHEET),
                          onInputChanged: (number) {
                            this.number = number;
                            setState(() {});
                          },
                        ),
                        isActive: step == 0),
                    Step(
                        title: Text('Enter OTP'),
                        content: TextField(
                            controller: _smsCode,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9]')),
                            ],
                            decoration: InputDecoration(
                                errorText: error2.isEmpty ? null : error2,
                                labelText: "OTP",
                                icon: Icon(Icons.phone_iphone))),
                        isActive: step == 1)
                  ],
                )
              ],
            ),
          ),
          isLoading: overlay),
    );
  }
}
