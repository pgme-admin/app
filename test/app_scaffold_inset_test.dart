import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/widgets/app_scaffold.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';

// The eBook Store and Your Notes lists ended with a fixed 100pt gap, but the
// floating bottom nav needs ~116pt on a notch iPhone, so the last card's Read
// button sat under the nav. They now end with AppScaffold.bottomContentInset.
void main() {
  testWidgets('last list item clears the floating bottom nav', (tester) async {
    // iPhone-sized screen with a home indicator (34pt bottom safe area).
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MiniPlayerProvider()),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/notes',
          routes: [
            GoRoute(
              path: '/notes',
              builder: (context, state) => AppScaffold(
                currentIndex: 3,
                child: Builder(
                  builder: (context) => ListView.builder(
                    padding: EdgeInsets.only(
                        bottom: AppScaffold.bottomContentInset(context)),
                    itemCount: 12,
                    itemBuilder: (_, i) => SizedBox(
                      height: 180,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                            key: Key('read-$i'), height: 44, width: 120),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    // Scroll to the very end.
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    // The floating nav: the 70pt-tall bar the scaffold positions at the bottom.
    final nav = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints != null &&
        w.constraints!.minHeight == 70 &&
        w.constraints!.maxHeight == 70);
    expect(nav, findsOneWidget);
    final navTop = tester.getTopLeft(nav).dy;

    final lastReadButtonBottom =
        tester.getBottomLeft(find.byKey(const Key('read-11'))).dy;
    expect(lastReadButtonBottom, lessThanOrEqualTo(navTop),
        reason: 'last Read button (bottom $lastReadButtonBottom) must end '
            'above the nav bar (top $navTop)');
  });
}
