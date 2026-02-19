import 'dart:async';
import 'package:flutter/material.dart';
import 'package:visitarian_flutter/core/services/services.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Timer? _quoteTimer;

  int _currentSlideIndex = 0; // 0..slides-1
  int _currentQuoteIndex = 0;

  // Each slide has an image + 5 quotes
  final List<Map<String, dynamic>> _slides = const [
    {
      'image': 'assets/images/onboarding/slide1.JPG',
      'quotes': [
        '"Find yourself where the land breathes."',
        '"Feel the calm of nature."',
        '"Let your mind wander."',
        '"Breathe in the view."',
        '"Start your journey here."',
      ],
    },
    {
      'image': 'assets/images/onboarding/slide2.JPG',
      'quotes': [
        '"Wander where the river sings."',
        '"Follow the flow of adventure."',
        "\"Nature's rhythm awaits.\"",
        '"Every stream tells a story."',
        '"Go where water leads."',
      ],
    },
    {
      'image': 'assets/images/onboarding/slide3.JPG',
      'quotes': [
        '"Discover places worth remembering."',
        '"Capture moments that matter."',
        '"Explore beyond the usual."',
        '"Find hidden gems."',
        '"Memories start here."',
      ],
    },
    {
      'image': 'assets/images/onboarding/slide4.JPG',
      'quotes': [
        '"Let the world be your guide."',
        '"Travel with purpose."',
        '"See more, feel more."',
        '"Explore with intention."',
        '"Let curiosity lead."',
      ],
    },
    {
      'image': 'assets/images/onboarding/slide5.JPG',
      'quotes': [
        '"Adventure is just a tap away."',
        '"Your next view is waiting."',
        '"Step into new places."',
        '"Explore anytime, anywhere."',
        '"Start the tour now."',
      ],
    },
  ];

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();

    // Start in the middle so user can swipe "forever" both directions
    final initialPage = 1000 * _slides.length;
    _pageController = PageController(initialPage: initialPage);

    _currentSlideIndex = initialPage % _slides.length;
    _currentQuoteIndex = 0;

    _startQuoteTimer();
  }

  void _startQuoteTimer() {
    _quoteTimer?.cancel();
    _quoteTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;

      final quotes = _slides[_currentSlideIndex]['quotes'] as List<String>;
      setState(() {
        _currentQuoteIndex = (_currentQuoteIndex + 1) % quotes.length;
      });
    });
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goToTours(BuildContext context) async {
    // Just mark onboarding as seen
    // The AuthGate StreamBuilder will automatically detect the change and rebuild
    await AuthService().markOnboardingAsSeen();
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFE3D6D6);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),

            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (pageIndex) {
                  final realIndex = pageIndex % _slides.length;
                  setState(() {
                    _currentSlideIndex = realIndex;
                    _currentQuoteIndex = 0; // reset quote when slide changes
                  });
                },
                itemBuilder: (context, pageIndex) {
                  final realIndex = pageIndex % _slides.length;

                  final imagePath = _slides[realIndex]['image'] as String;
                  final quotes = _slides[realIndex]['quotes'] as List<String>;

                  // Rotating quotes only on current slide
                  final quoteToShow = (realIndex == _currentSlideIndex)
                      ? quotes[_currentQuoteIndex]
                      : quotes[0];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _OnboardingCard(
                      quote: quoteToShow,
                      imagePath: imagePath,
                      onArrowTap: () => _goToTours(context),
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 10),
              child: _DashIndicator(
                count: _slides.length,
                currentIndex: _currentSlideIndex,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  final String quote;
  final String imagePath;
  final VoidCallback onArrowTap;

  const _OnboardingCard({
    required this.quote,
    required this.imagePath,
    required this.onArrowTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(child: Image.asset(imagePath, fit: BoxFit.cover)),

          // Overlay for readability
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),

          // Quote + arrow
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        quote,
                        key: ValueKey(quote),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _ArrowButton(onTap: onArrowTap),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ArrowButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const pillGreen = Color(0xFF1B5A45);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: pillGreen,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.arrow_forward, color: Colors.white),
      ),
    );
  }
}

class _DashIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _DashIndicator({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 26 : 18,
          height: 4,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1B5A45) : Colors.black26,
            borderRadius: BorderRadius.circular(10),
          ),
        );
      }),
    );
  }
}
